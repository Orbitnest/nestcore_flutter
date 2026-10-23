// Memory, collections, threads and traces against a local HTTP server: wire
// format (paths, camelCase bodies, query strings), snake_case row parsing,
// typed errors, no retry of writes, ingest polling, SSE run events and
// cancel-on-unsubscribe.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbitnest_studio_flutter/src/ai/ai_data.dart';
import 'package:orbitnest_studio_flutter/src/ai/ai_data_models.dart';
import 'package:orbitnest_studio_flutter/src/ai/orbitnest_ai.dart';
import 'package:orbitnest_studio_flutter/src/auth/services/token_manager.dart';
import 'package:orbitnest_studio_flutter/src/client/http_client.dart';
import 'package:orbitnest_studio_flutter/src/utils/env_config.dart';

const _base = '/api/project/demo/ai/v1';

Map<String, dynamic> _memoryRow(String id, {String content = 'Likes tea', Object importance = 4}) => {
      'id': id,
      'subject_type': 'user',
      'subject_id': 'u1',
      'kind': 'preference',
      'content': content,
      'embed_model': 'mock-embed',
      'importance': importance,
      'metadata': {'src': 'chat'},
      'source_thread_id': null,
      'expires_at': null,
      'created_at': '2026-10-20T10:00:00.000Z',
      'updated_at': '2026-10-21T10:00:00.000Z',
    };

Map<String, dynamic> _docRow(String id, String status) => {
      'id': id,
      'collection_id': 'c1',
      'owner_user_id': 'u1',
      'source_type': 'text',
      'source_ref': null,
      'title': 'Notes',
      'metadata': {},
      'status': status,
      'error': null,
      'chunk_count': status == 'ready' ? 2 : 0,
      'bytes': 40,
      'created_at': '2026-10-20T10:00:00.000Z',
      'updated_at': '2026-10-20T10:00:01.000Z',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding answers every real HTTP request with 400; this test talks to a real local server.
  HttpOverrides.global = null;
  FlutterSecureStorage.setMockInitialValues({});
  setUpAll(() => EnvConfig.initialize());

  late HttpServer server;
  late OrbitNestHttpClient http;
  late OrbitNestMemory memory;
  late OrbitNestCollections collections;
  late OrbitNestAi ai;
  final requests = <({String method, String path, Map<String, String> query, Object? body})>[];
  late Future<void> Function(HttpRequest req, Object? body) handler;

  setUp(() async {
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final raw = await utf8.decodeStream(req);
      final body = raw.isEmpty ? null : jsonDecode(raw);
      requests.add((method: req.method, path: req.uri.path, query: req.uri.queryParameters, body: body));
      await handler(req, body);
    });
    http = OrbitNestHttpClient(baseUrl: 'http://127.0.0.1:${server.port}', tokenManager: TokenManager(projectSlug: 'demo', apiKey: 'anon'));
    memory = OrbitNestMemory(httpClient: http, projectSlug: 'demo');
    collections = OrbitNestCollections(httpClient: http, projectSlug: 'demo');
    ai = OrbitNestAi(httpClient: http, projectSlug: 'demo');
  });

  tearDown(() => server.close(force: true));

  Future<void> json(HttpRequest req, Object body, [int status = 200]) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  }

  Future<void> sse(HttpRequest req, List<Map<String, dynamic>> events) async {
    req.response.headers.contentType = ContentType('text', 'event-stream');
    for (final e in events) {
      req.response.add(utf8.encode('data: ${jsonEncode(e)}\n\n'));
      await req.response.flush();
    }
    await req.response.close();
  }

  group('memory', () {
    test('add sends camelCase options and parses the snake_case row', () async {
      handler = (req, body) => json(req, {'memory': _memoryRow('m1', importance: '4'), 'deduped': true});
      final r = await memory.add(
        'Likes tea',
        kind: 'preference',
        importance: 4,
        expiresAt: DateTime.utc(2027, 1, 2),
        metadata: {'src': 'chat'},
        sourceThreadId: 't1',
        dedupe: false,
      );
      final sent = requests.single;
      expect(sent.method, 'POST');
      expect(sent.path, '$_base/memory');
      expect(sent.body, {
        'content': 'Likes tea',
        'kind': 'preference',
        'importance': 4,
        'expiresAt': '2027-01-02T00:00:00.000Z',
        'metadata': {'src': 'chat'},
        'sourceThreadId': 't1',
        'dedupe': false,
      });
      expect(r.deduped, isTrue);
      expect(r.memory.id, 'm1');
      expect(r.memory.subject, 'user:u1');
      expect(r.memory.importance, 4); // numeric strings are accepted
      expect(r.memory.metadata['src'], 'chat');
      expect(r.memory.updatedAt, DateTime.utc(2026, 10, 21, 10));
    });

    test('search parses similarity, score, degraded and usage', () async {
      handler = (req, body) => json(req, {
            'results': [
              {..._memoryRow('m1'), 'similarity': 0.81, 'score': 0.9},
              {..._memoryRow('m2'), 'similarity': null, 'score': '0.2'},
            ],
            'degraded': false,
            'model': 'mock-embed',
            'usage': {'tokensIn': 5, 'costUsd': 0.0001},
          });
      final r = await memory.search('tea?', k: 3, kind: 'preference', minSimilarity: 0.3, subject: 'user:u1');
      expect(requests.single.path, '$_base/memory/search');
      expect(requests.single.body, {'query': 'tea?', 'subject': 'user:u1', 'k': 3, 'kind': 'preference', 'minSimilarity': 0.3});
      expect(r.results.first.memory.id, 'm1');
      expect(r.results.first.similarity, 0.81);
      expect(r.results.last.similarity, isNull);
      expect(r.results.last.score, 0.2);
      expect(r.degraded, isFalse);
      expect(r.model, 'mock-embed');
      expect(r.tokensIn, 5);
    });

    test('list/get/update/remove/forget/subjects/reembed hit the right routes', () async {
      handler = (req, body) {
        final p = req.uri.path;
        if (p.endsWith('/memory/subjects')) {
          return json(req, [
            {'subject': 'user:u1', 'subject_type': 'user', 'subject_id': 'u1', 'memories': '3', 'last_updated': '2026-10-21T10:00:00Z'}
          ]);
        }
        if (p.endsWith('/memory/forget')) return json(req, {'deleted': 3});
        if (p.endsWith('/memory/reembed')) return json(req, {'reembedded': 2, 'remaining': 0, 'model': 'm'});
        if (p.endsWith('/memory')) return json(req, {'memories': [_memoryRow('m1')], 'total': 1});
        if (req.method == 'DELETE') return json(req, {'deleted': true});
        return json(req, _memoryRow('m1', content: 'x'));
      };
      final page = await memory.list(kind: 'preference', limit: 10, offset: 5);
      expect(page.total, 1);
      expect(page.memories.single.kind, 'preference');
      expect((await memory.get('m1')).content, 'x');
      await memory.update('m1', content: 'x', clearExpiresAt: true);
      expect(await memory.remove('m1'), isTrue);
      expect(await memory.forget(), 3);
      final subjects = await memory.subjects(type: 'user');
      expect(subjects.single.memories, 3);
      expect((await memory.reembed(limit: 64)).reembedded, 2);

      expect(requests.map((r) => '${r.method} ${r.path.replaceFirst(_base, '')}'), [
        'GET /memory',
        'GET /memory/m1',
        'PATCH /memory/m1',
        'DELETE /memory/m1',
        'POST /memory/forget',
        'GET /memory/subjects',
        'POST /memory/reembed',
      ]);
      expect(requests[0].query, {'kind': 'preference', 'limit': '10', 'offset': '5'});
      expect(requests[2].body, {'content': 'x', 'expiresAt': null});
      expect(requests[4].body, <String, dynamic>{});
      expect(requests[5].query, {'type': 'user'});
      expect(requests[6].body, {'limit': 64});
    });

    test('errors are typed AiExceptions and writes are not retried', () async {
      handler = (req, body) => json(req, {'code': 'AI_PROVIDER_ERROR', 'message': 'down', 'statusCode': 502}, 502);
      await expectLater(
        memory.add('x'),
        throwsA(isA<AiException>().having((e) => e.code, 'code', 'AI_PROVIDER_ERROR').having((e) => e.statusCode, 'status', 502)),
      );
      expect(requests.length, 1);

      handler = (req, body) => json(req, {'statusCode': 401, 'message': 'Sign in first'}, 401);
      await expectLater(memory.list(), throwsA(isA<AiException>().having((e) => e.statusCode, 'status', 401)));
    });
  });

  group('collections', () {
    test('create/list/get/update/delete and stats', () async {
      final row = {
        'id': 'c1',
        'name': 'kb',
        'embed_model': 'mock-embed',
        'embed_provider': 'openai_compatible',
        'chunk_tokens': 400,
        'chunk_overlap': 60,
        'user_ingest': true,
        'metadata': {},
        'created_at': '2026-10-20T10:00:00Z',
      };
      handler = (req, body) {
        final p = req.uri.path;
        if (p.endsWith('/stats')) return json(req, {'chunks': 4, 'current_model_chunks': 4, 'documents': 2, 'failed': 0, 'model': 'mock-embed'});
        if (req.method == 'DELETE') return json(req, {'deleted': true});
        if (req.method == 'GET' && p.endsWith('/collections')) return json(req, [{...row, 'documents': 2, 'pending': 1}]);
        return json(req, row);
      };
      final c = await collections.create(name: 'kb', userIngest: true, chunkTokens: 300, provider: 'openai_compatible');
      expect(c.userIngest, isTrue);
      expect(c.embedProvider, 'openai_compatible');
      final all = await collections.list();
      expect(all.single.pending, 1);
      await collections.get('kb');
      await collections.update('kb', userIngest: false, metadata: {'a': 1});
      expect(await collections.delete('kb'), isTrue);
      final stats = await collections.from('kb').stats();
      expect(stats.currentModelChunks, 4);

      expect(requests[0].body, {'name': 'kb', 'provider': 'openai_compatible', 'chunkTokens': 300, 'userIngest': true});
      expect(requests[3].body, {'userIngest': false, 'metadata': {'a': 1}});
      expect(requests.map((r) => '${r.method} ${r.path.replaceFirst(_base, '')}'), [
        'POST /collections',
        'GET /collections',
        'GET /collections/kb',
        'PATCH /collections/kb',
        'DELETE /collections/kb',
        'GET /collections/kb/stats',
      ]);
    });

    test('ingest merges the source into the body and, with wait, polls until ready', () async {
      var polls = 0;
      handler = (req, body) {
        if (req.method == 'POST') return json(req, _docRow('d1', 'queued'));
        polls++;
        return json(req, _docRow('d1', polls < 3 ? 'processing' : 'ready'));
      };
      final doc = await collections.from('kb').ingest(
            AiDocumentSource.storage(bucket: 'docs', path: 'a/guide.pdf'),
            title: 'Guide',
            metadata: {'team': 'support'},
            wait: true,
            interval: const Duration(milliseconds: 5),
          );
      expect(requests.first.path, '$_base/collections/kb/documents');
      expect(requests.first.body, {
        'storage': {'bucket': 'docs', 'path': 'a/guide.pdf'},
        'title': 'Guide',
        'metadata': {'team': 'support'},
      });
      expect(requests.skip(1).every((r) => r.method == 'GET' && r.path == '$_base/collections/kb/documents/d1'), isTrue);
      expect(doc.isReady, isTrue);
      expect(doc.chunkCount, 2);
      expect(polls, 3);
    });

    test('ingest without wait returns queued; waitFor times out with TIMEOUT', () async {
      handler = (req, body) => json(req, _docRow('d1', 'queued'));
      final ref = collections.from('kb');
      final doc = await ref.ingest(AiDocumentSource.text('hello'));
      expect(doc.status, 'queued');
      expect(requests.single.body, {'text': 'hello'});
      await expectLater(
        ref.waitFor('d1', timeout: const Duration(milliseconds: 30), interval: const Duration(milliseconds: 10)),
        throwsA(isA<AiException>().having((e) => e.code, 'code', 'TIMEOUT')),
      );
    });

    test('search parses chunks, documents and highlights; names are path-encoded', () async {
      handler = (req, body) => json(req, {
            'results': [
              {
                'score': 0.0328,
                'similarity': 0.7,
                'keywordMatch': true,
                'highlight': 'how **refunds** work',
                'chunk': {'id': 'k1', 'ordinal': 0, 'content': 'Refunds go to the card.', 'metadata': {}},
                'document': {'id': 'd1', 'title': 'Policy', 'sourceType': 'url', 'sourceRef': 'https://x', 'metadata': {'team': 'support'}},
              }
            ],
            'model': 'mock-embed',
            'usage': {'tokensIn': 3, 'costUsd': 0},
          });
      final r = await collections.from('my kb').search('refunds', k: 2, hybrid: false, filter: {'team': 'support'}, minSimilarity: 0.1);
      expect(requests.single.path, '$_base/collections/my%20kb/search');
      expect(requests.single.body, {'query': 'refunds', 'k': 2, 'hybrid': false, 'filter': {'team': 'support'}, 'minSimilarity': 0.1});
      final hit = r.results.single;
      expect(hit.keywordMatch, isTrue);
      expect(hit.highlight, contains('**'));
      expect(hit.chunk.content, startsWith('Refunds'));
      expect(hit.document.sourceType, 'url');
      expect(hit.document.metadata['team'], 'support');
      expect(r.model, 'mock-embed');
    });

    test('listDocuments / getDocument / remove', () async {
      handler = (req, body) {
        if (req.method == 'DELETE') return json(req, {'deleted': false});
        if (req.uri.path.endsWith('/documents')) return json(req, {'documents': [_docRow('d1', 'failed')], 'total': 1});
        return json(req, _docRow('d1', 'ready'));
      };
      final ref = collections.from('kb');
      final page = await ref.listDocuments(status: 'failed', limit: 5);
      expect(page.documents.single.isFailed, isTrue);
      expect(requests.first.query, {'status': 'failed', 'limit': '5'});
      expect((await ref.getDocument('d1')).isDone, isTrue);
      expect(await ref.remove('d1'), isFalse);
    });
  });

  group('threads', () {
    final threadRow = {
      'id': 't1',
      'owner_user_id': 'u1',
      'title': 'Trip',
      'metadata': {},
      'created_at': '2026-10-20T10:00:00Z',
      'updated_at': '2026-10-20T10:00:00Z',
    };

    test('create/list/get/update/delete/messages/append', () async {
      handler = (req, body) {
        final p = req.uri.path;
        if (p.endsWith('/messages') && req.method == 'GET') {
          return json(req, [
            {
              'id': 'msg1',
              'thread_id': 't1',
              'role': 'assistant',
              'content': [
                {'type': 'text', 'text': 'Hello '},
                {'type': 'text', 'text': 'there'},
              ],
              'model': 'mock-1',
              'provider': 'openai_compatible',
              'tokens_in': 3,
              'tokens_out': 2,
              'cost_usd': '0.000100',
              'status': 'complete',
              'error': null,
              'metadata': {},
              'created_at': '2026-10-20T10:00:00Z',
            }
          ]);
        }
        if (p.endsWith('/messages')) {
          return json(req, {
            'id': 'msg2',
            'thread_id': 't1',
            'role': 'user',
            'content': (body as Map)['content'] is String ? [{'type': 'text', 'text': body['content']}] : body['content'],
            'status': 'complete',
            'metadata': {},
          });
        }
        if (req.method == 'GET' && p.endsWith('/threads')) return json(req, {'threads': [{...threadRow, 'messages': 4, 'cost_usd': 0.02}], 'total': 1});
        if (req.method == 'DELETE') return json(req, {'deleted': true});
        return json(req, threadRow);
      };
      final t = await ai.threads.create(title: 'Trip', metadata: {'a': 1});
      expect(t.ownerUserId, 'u1');
      final page = await ai.threads.list(limit: 20);
      expect(page.threads.single.messages, 4);
      expect(page.threads.single.costUsd, 0.02);
      await ai.threads.get('t1');
      final ref = ai.threads.from('t1');
      await ref.update(clearTitle: true, metadata: {'b': 2});
      final msgs = await ref.messages(limit: 10, after: 'msg0');
      expect(msgs.single.text, 'Hello there');
      expect(msgs.single.costUsd, 0.0001);
      final appended = await ref.append([
        const AiThreadPart.text('What is this?'),
        const AiThreadPart.storage(bucket: 'photos', path: 'u1/cat.png'),
        const AiContentPart.image('data:image/png;base64,AAAA'),
      ]);
      expect(appended.content[1].bucket, 'photos');
      expect(appended.content[2].url, startsWith('data:'));
      expect(await ai.threads.delete('t1'), isTrue);

      expect(requests.map((r) => '${r.method} ${r.path.replaceFirst(_base, '')}'), [
        'POST /threads',
        'GET /threads',
        'GET /threads/t1',
        'PATCH /threads/t1',
        'GET /threads/t1/messages',
        'POST /threads/t1/messages',
        'DELETE /threads/t1',
      ]);
      expect(requests[0].body, {'title': 'Trip', 'metadata': {'a': 1}});
      expect(requests[1].query, {'limit': '20'});
      expect(requests[3].body, {'title': null, 'metadata': {'b': 2}});
      expect(requests[4].query, {'limit': '10', 'after': 'msg0'});
      expect(requests[5].body, {
        'content': [
          {'type': 'text', 'text': 'What is this?'},
          {'type': 'image', 'storage': {'bucket': 'photos', 'path': 'u1/cat.png'}},
          {'type': 'image', 'url': 'data:image/png;base64,AAAA'},
        ],
      });
    });

    test('run streams typed events, skips unknown ones, and sends stream:true', () async {
      handler = (req, body) => sse(req, [
            {'type': 'message', 'threadId': 't1', 'messageId': 'msg9'},
            {'type': 'citation', 'index': 1, 'collection': 'kb', 'documentId': 'd1', 'chunkId': 'k1', 'title': 'Policy', 'sourceRef': null, 'snippet': 'Refunds…', 'score': 0.03},
            {'type': 'delta', 'text': 'Hello '},
            {'type': 'tool_call', 'id': 'c1', 'name': 'memory_search', 'arguments': {'query': 'dog'}},
            {'type': 'tool_result', 'id': 'c1', 'name': 'memory_search', 'result': [{'content': 'Has a dog'}]},
            {'type': 'future_event', 'x': 1},
            {'type': 'delta', 'text': 'there [1]'},
            {'type': 'done', 'messageId': 'msg9', 'model': 'mock-1', 'provider': 'openai_compatible', 'tokensIn': 10, 'tokensOut': 4, 'costUsd': 0.0012},
          ]);
      final events = await ai.threads
          .from('t1')
          .run(input: 'Hi', memory: true, collections: ['kb'], tools: [AiThreadTool.memorySearch], maxContextTokens: 4000, temperature: 0.2)
          .toList();
      expect(requests.single.path, '$_base/threads/t1/run');
      expect(requests.single.body, {
        'input': 'Hi',
        'temperature': 0.2,
        'memory': true,
        'collections': ['kb'],
        'tools': ['memory_search'],
        'maxContextTokens': 4000,
        'stream': true,
      });
      expect(events.first, isA<ThreadRunMessage>().having((e) => e.messageId, 'messageId', 'msg9'));
      expect(events.whereType<ThreadRunCitation>().single.citation.collection, 'kb');
      expect(events.whereType<ThreadRunDelta>().map((e) => e.text).join(), 'Hello there [1]');
      expect(events.whereType<ThreadRunToolCall>().single.call.arguments['query'], 'dog');
      expect(events.whereType<ThreadRunToolResult>().single.result, [
        {'content': 'Has a dog'}
      ]);
      expect(events.length, 7); // the unknown event is skipped
      final done = events.last as ThreadRunDone;
      expect(done.costUsd, 0.0012);
      expect(done.provider, 'openai_compatible');
    });

    test('run reports a rejected request and a mid-stream error as ThreadRunError', () async {
      handler = (req, body) => json(req, {'statusCode': 404, 'message': 'Thread not found'}, 404);
      final rejected = await ai.threads.from('nope').run(input: 'x').toList();
      expect(rejected.single, isA<ThreadRunError>().having((e) => e.statusCode, 'status', 404).having((e) => e.message, 'message', 'Thread not found'));

      handler = (req, body) => sse(req, [
            {'type': 'message', 'threadId': 't1', 'messageId': 'm'},
            {'type': 'error', 'code': 'AI_PROVIDER_ERROR', 'message': 'boom'},
          ]);
      final failed = await ai.threads.from('t1').run().toList();
      expect(failed.last, isA<ThreadRunError>().having((e) => e.code, 'code', 'AI_PROVIDER_ERROR'));

      final bad = await ai.threads.from('t1').run(memory: 42).toList();
      expect(bad.single, isA<ThreadRunError>().having((e) => e.code, 'code', 'INVALID_ARGUMENT'));
    });

    test('runOnce sends stream:false and parses the finished message', () async {
      handler = (req, body) => json(req, {
            'messageId': 'msg9',
            'text': 'You have a dog.',
            'citations': [],
            'toolCalls': [
              {'id': 'c1', 'name': 'memory_search', 'result': [{'content': 'Has a dog'}]}
            ],
            'usage': {'model': 'mock-1', 'provider': null, 'tokensIn': 5, 'tokensOut': 4, 'costUsd': 0.001},
          });
      final r = await ai.threads.from('t1').runOnce(input: 'dog?', memory: 'user:u1', tools: AiThreadTool.values, model: 'mock-1');
      expect(requests.single.body, {
        'input': 'dog?',
        'model': 'mock-1',
        'memory': 'user:u1',
        'tools': ['memory_search', 'collections_search'],
        'stream': false,
      });
      expect(r.text, 'You have a dog.');
      expect(r.toolResults.single.name, 'memory_search');
      expect(r.usage?.tokensOut, 4);
    });

    test('cancelling a run closes the connection', () async {
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
      final streamingHttp = OrbitNestHttpClient(baseUrl: 'http://127.0.0.1:${raw.port}', tokenManager: TokenManager(projectSlug: 'demo', apiKey: 'anon'));
      final threads = AiThreads(httpClient: streamingHttp, projectSlug: 'demo');

      final firstFew = Completer<void>();
      var seen = 0;
      final sub = threads.from('t1').run(input: 'long').listen((e) {
        if (++seen == 3 && !firstFew.isCompleted) firstFew.complete();
      });
      await firstFew.future.timeout(const Duration(seconds: 5));
      await sub.cancel();
      await clientGone.future.timeout(const Duration(seconds: 2));
      expect(seen, lessThan(20));
      await raw.close();
    });
  });

  test('traces sends filters as query params and parses the page', () async {
    handler = (req, body) => json(req, {
          'traces': [
            {
              'id': 'tr1',
              'request_id': 'r1',
              'thread_id': 't1',
              'caller': 'sdk',
              'kind': 'chat',
              'end_user_id': 'u1',
              'provider': 'openai_compatible',
              'model': 'mock-1',
              'key_source': 'byok',
              'prompt_hash': 'abc',
              'tokens_in': 10,
              'tokens_out': 4,
              'cost_usd': 0.0012,
              'latency_ms': 120,
              'status': 'ok',
              'error': null,
              'created_at': '2026-10-20T10:00:00Z',
            }
          ],
          'total': 1,
          'retentionDays': 7,
        });
    final page = await ai.traces(limit: 50, threadId: 't1', status: 'ok');
    expect(requests.single.path, '$_base/traces');
    expect(requests.single.query, {'limit': '50', 'threadId': 't1', 'status': 'ok'});
    expect(page.retentionDays, 7);
    expect(page.traces.single.latencyMs, 120);
    expect(page.traces.single.keySource, 'byok');
  });
}
