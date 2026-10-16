// OrbitNestAi against a local HTTP server: wire format, tool calls, SSE parsing,
// typed errors, no retry of billed calls, and cancel-on-unsubscribe.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbitnest_studio_flutter/src/ai/orbitnest_ai.dart';
import 'package:orbitnest_studio_flutter/src/auth/services/token_manager.dart';
import 'package:orbitnest_studio_flutter/src/client/http_client.dart';
import 'package:orbitnest_studio_flutter/src/utils/env_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding answers every real HTTP request with 400; this test talks to a real local server.
  HttpOverrides.global = null;
  FlutterSecureStorage.setMockInitialValues({});
  setUpAll(() => EnvConfig.initialize());

  late HttpServer server;
  late OrbitNestAi ai;
  final requests = <Map<String, dynamic>>[];
  late Future<void> Function(HttpRequest req, Map<String, dynamic> body) handler;

  setUp(() async {
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final raw = await utf8.decodeStream(req);
      final body = raw.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(raw) as Map);
      requests.add({'path': req.uri.path, ...body});
      await handler(req, body);
    });
    final http = OrbitNestHttpClient(baseUrl: 'http://127.0.0.1:${server.port}', tokenManager: TokenManager(projectSlug: 'demo', apiKey: 'anon'));
    ai = OrbitNestAi(httpClient: http, projectSlug: 'demo');
  });

  tearDown(() => server.close(force: true));

  Future<void> json(HttpRequest req, Object body, [int status = 200]) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  }

  test('chat sends snake_case messages, parts and tools; parses toolCalls', () async {
    handler = (req, body) => json(req, {
          'text': '',
          'toolCalls': [
            {'id': 'c1', 'name': 'get_weather', 'arguments': {'city': 'Oslo'}, 'signature': 's'}
          ],
          'model': 'm',
          'provider': 'gemini',
          'tokensIn': 3,
          'tokensOut': 1,
          'costUsd': 0.001,
        });
    final r = await ai.chat(
      messages: [
        const AiMessage(role: 'user', parts: [AiContentPart.text('hi'), AiContentPart.image('data:image/png;base64,AAAA')]),
        AiMessage.toolResult(const AiToolCall(id: 'c0', name: 'x'), '42'),
      ],
      tools: const [AiTool(name: 'get_weather', parameters: {'type': 'object'})],
      toolChoice: 'get_weather',
      maxTokens: 9,
    );
    expect(r.toolCalls.single.arguments['city'], 'Oslo');
    expect(r.toolCalls.single.signature, 's');
    final sent = requests.single;
    expect(sent['path'], '/api/project/demo/ai/v1/chat');
    expect((sent['messages'] as List)[0]['content'][1], {'type': 'image', 'url': 'data:image/png;base64,AAAA'});
    expect((sent['messages'] as List)[1], {'role': 'tool', 'content': '42', 'tool_call_id': 'c0'});
    expect(sent['tool_choice'], {'name': 'get_weather'});
    expect(sent['max_tokens'], 9);
    expect(sent['stream'], false);

    // The reply goes back into the history with its calls intact.
    expect(AiMessage.fromResult(r).toJson()['tool_calls'], [
      {'id': 'c1', 'name': 'get_weather', 'arguments': {'city': 'Oslo'}, 'signature': 's'}
    ]);
  });

  test('a gateway error becomes a typed AiException with its body', () async {
    handler = (req, body) => json(req, {'code': 'AI_BUDGET_EXCEEDED', 'message': 'used up', 'scope': 'user'}, 402);
    await expectLater(
      ai.chat(messages: const [AiMessage.user('hi')]),
      throwsA(isA<AiException>().having((e) => e.code, 'code', 'AI_BUDGET_EXCEEDED').having((e) => e.statusCode, 'status', 402).having((e) => e.body?['scope'], 'scope', 'user')),
    );
  });

  test('a provider 500 is not retried (a resend would pay twice)', () async {
    handler = (req, body) => json(req, {'code': 'AI_PROVIDER_ERROR', 'message': 'boom'}, 502);
    await expectLater(ai.chat(messages: const [AiMessage.user('hi')]), throwsA(isA<AiException>()));
    expect(requests.length, 1);
  });

  test('chatStream yields deltas, tool calls and done', () async {
    handler = (req, body) async {
      req.response.headers.contentType = ContentType('text', 'event-stream');
      for (final e in [
        {'type': 'delta', 'text': 'He'},
        {'type': 'delta', 'text': 'llo'},
        {'type': 'tool_call', 'id': 'c1', 'name': 'get_weather', 'arguments': {'city': 'Oslo'}},
        {'type': 'done', 'model': 'm', 'tokensIn': 2, 'tokensOut': 3, 'costUsd': 0.01, 'finishReason': 'stop'},
      ]) {
        req.response.write('data: ${jsonEncode(e)}\n\n');
        await req.response.flush();
      }
      await req.response.close();
    };
    final events = await ai.chatStream(messages: const [AiMessage.user('hi')]).toList();
    expect(events.whereType<AiTextDelta>().map((e) => e.text).join(), 'Hello');
    expect(events.whereType<AiToolCallEvent>().single.call.name, 'get_weather');
    expect((events.last as AiStreamDone).tokensOut, 3);
    expect(requests.single['stream'], true);
  });

  test('chatStream reports a rejected request as one AiStreamError', () async {
    handler = (req, body) => json(req, {'code': 'AI_PROVIDER_NOT_CONFIGURED', 'message': 'no key'}, 400);
    final events = await ai.chatStream(messages: const [AiMessage.user('hi')]).toList();
    expect(events.single, isA<AiStreamError>().having((e) => e.code, 'code', 'AI_PROVIDER_NOT_CONFIGURED').having((e) => e.statusCode, 'status', 400));
  });

  test('cancelling the subscription closes the connection', () async {
    // A raw socket server: Dart's HttpServer never reports a client that went away
    // mid-response, but a raw socket sees end-of-stream when the client destroys it.
    final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final clientGone = Completer<void>();
    raw.listen((socket) {
      var headersSent = false;
      socket.listen((_) async {
        if (headersSent) return;
        headersSent = true;
        socket.write('HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\nconnection: close\r\n\r\n');
        for (var i = 0; i < 200 && !clientGone.isCompleted; i++) {
          socket.write('data: ${jsonEncode({'type': 'delta', 'text': '$i '})}\n\n');
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }, onDone: () {
        if (!clientGone.isCompleted) clientGone.complete();
      }, onError: (_) {
        if (!clientGone.isCompleted) clientGone.complete();
      });
    });
    final http = OrbitNestHttpClient(baseUrl: 'http://127.0.0.1:${raw.port}', tokenManager: TokenManager(projectSlug: 'demo', apiKey: 'anon'));
    final streaming = OrbitNestAi(httpClient: http, projectSlug: 'demo');

    final firstFew = Completer<void>();
    var seen = 0;
    final sub = streaming.chatStream(messages: const [AiMessage.user('hi')]).listen((e) {
      if (++seen == 3 && !firstFew.isCompleted) firstFew.complete();
    });
    await firstFew.future.timeout(const Duration(seconds: 5));
    await sub.cancel();
    await clientGone.future.timeout(const Duration(seconds: 2));
    expect(seen, lessThan(20));
    await raw.close();
  });
}
