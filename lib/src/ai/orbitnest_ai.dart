import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import '../client/http_client.dart';
import '../client/interceptors/error_interceptor.dart';

/// Thrown by [OrbitNestAi.chat], [OrbitNestAi.embed] and [OrbitNestAi.models].
///
/// [code] is the gateway code, e.g. `AI_PROVIDER_NOT_CONFIGURED`,
/// `AI_BUDGET_EXCEEDED` (402, [body] holds `scope`, `limitUsd`, `usedUsd`) or
/// `AI_RATE_LIMITED` (429, [body] holds `retryAfterSec`).
class AiException extends OrbitNestException {
  const AiException(super.message, {super.code, super.statusCode, super.body});

  static Future<AiException> fromError(Object error) async {
    if (error is AiException) return error;
    if (error is DioException) {
      final wrapped = error.error is OrbitNestException ? error.error as OrbitNestException : null;
      Map<String, dynamic>? body = wrapped?.body;
      final raw = error.response?.data;
      if (body == null && raw is Map) {
        body = Map<String, dynamic>.from(raw);
      }
      final m = body?['message'] ?? body?['error'];
      return AiException(
        m is List ? m.join(', ') : m?.toString() ?? wrapped?.message ?? error.message ?? 'AI request failed',
        code: body?['code']?.toString() ?? wrapped?.code,
        statusCode: error.response?.statusCode ?? wrapped?.statusCode,
        body: body,
      );
    }
    if (error is OrbitNestException) {
      return AiException(error.message, code: error.code, statusCode: error.statusCode, body: error.body);
    }
    return AiException(error.toString(), code: 'UNKNOWN_AI_ERROR');
  }

  @override
  String toString() => code != null ? 'AiException($code): $message' : 'AiException: $message';
}

/// One part of a message: text, or an image as a `data:image/png;base64,…`
/// URL (or an https URL with OpenAI and Anthropic).
class AiContentPart {
  final String type;
  final String? text;
  final String? url;

  const AiContentPart.text(String this.text)
      : type = 'text',
        url = null;
  const AiContentPart.image(String this.url)
      : type = 'image',
        text = null;

  Map<String, dynamic> toJson() => type == 'text' ? {'type': 'text', 'text': text} : {'type': 'image', 'url': url};
}

/// A call the model asked for. Send it back unchanged in the assistant
/// message ([signature] carries provider state some models require).
class AiToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final String? signature;

  const AiToolCall({required this.id, required this.name, this.arguments = const {}, this.signature});

  factory AiToolCall.fromJson(Map<String, dynamic> j) => AiToolCall(
        id: j['id'] as String,
        name: j['name'] as String,
        arguments: Map<String, dynamic>.from((j['arguments'] as Map?) ?? const {}),
        signature: j['signature'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'arguments': arguments,
        if (signature != null) 'signature': signature,
      };
}

/// A tool the model may call. [parameters] is the JSON Schema of the arguments.
class AiTool {
  final String name;
  final String? description;
  final Map<String, dynamic>? parameters;

  const AiTool({required this.name, this.description, this.parameters});

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        if (parameters != null) 'parameters': parameters,
      };
}

class AiMessage {
  /// `system`, `user`, `assistant` or `tool`.
  final String role;

  /// Plain text; use [parts] for images.
  final String? content;
  final List<AiContentPart>? parts;

  /// assistant: calls from a previous reply.
  final List<AiToolCall>? toolCalls;

  /// tool: the id of the call this result answers.
  final String? toolCallId;

  const AiMessage({required this.role, this.content, this.parts, this.toolCalls, this.toolCallId});

  const AiMessage.system(String text) : this(role: 'system', content: text);
  const AiMessage.user(String text) : this(role: 'user', content: text);
  const AiMessage.assistant(String text) : this(role: 'assistant', content: text);

  /// The model's reply, ready to append to the history (keeps its tool calls).
  factory AiMessage.fromResult(AiChatResult r) =>
      AiMessage(role: 'assistant', content: r.text, toolCalls: r.toolCalls.isEmpty ? null : r.toolCalls);

  /// The result of running [call].
  factory AiMessage.toolResult(AiToolCall call, String result) =>
      AiMessage(role: 'tool', content: result, toolCallId: call.id);

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': parts != null ? parts!.map((p) => p.toJson()).toList() : content,
        if (toolCalls != null) 'tool_calls': toolCalls!.map((c) => c.toJson()).toList(),
        if (toolCallId != null) 'tool_call_id': toolCallId,
      };
}

class AiChatResult {
  final String text;
  final List<AiToolCall> toolCalls;
  final String model;
  final String provider;
  final int tokensIn;
  final int tokensOut;
  final double costUsd;
  final String? finishReason;

  const AiChatResult({
    required this.text,
    required this.toolCalls,
    required this.model,
    required this.provider,
    required this.tokensIn,
    required this.tokensOut,
    required this.costUsd,
    this.finishReason,
  });

  factory AiChatResult.fromJson(Map<String, dynamic> j) => AiChatResult(
        text: (j['text'] as String?) ?? '',
        toolCalls: ((j['toolCalls'] as List?) ?? const [])
            .map((c) => AiToolCall.fromJson(Map<String, dynamic>.from(c as Map)))
            .toList(),
        model: (j['model'] as String?) ?? '',
        provider: (j['provider'] as String?) ?? '',
        tokensIn: (j['tokensIn'] as num?)?.toInt() ?? 0,
        tokensOut: (j['tokensOut'] as num?)?.toInt() ?? 0,
        costUsd: (j['costUsd'] as num?)?.toDouble() ?? 0,
        finishReason: j['finishReason'] as String?,
      );
}

/// Events of [OrbitNestAi.chatStream].
sealed class AiStreamEvent {
  const AiStreamEvent();

  static AiStreamEvent fromJson(Map<String, dynamic> j) => switch (j['type']) {
        'delta' => AiTextDelta(j['text'] as String? ?? ''),
        'tool_call' => AiToolCallEvent(AiToolCall.fromJson(j)),
        'done' => AiStreamDone(
            model: j['model'] as String? ?? '',
            tokensIn: (j['tokensIn'] as num?)?.toInt() ?? 0,
            tokensOut: (j['tokensOut'] as num?)?.toInt() ?? 0,
            costUsd: (j['costUsd'] as num?)?.toDouble() ?? 0,
            finishReason: j['finishReason'] as String?,
          ),
        _ => AiStreamError(j['message']?.toString() ?? 'Stream failed', code: j['code']?.toString()),
      };
}

class AiTextDelta extends AiStreamEvent {
  final String text;
  const AiTextDelta(this.text);
}

class AiToolCallEvent extends AiStreamEvent {
  final AiToolCall call;
  const AiToolCallEvent(this.call);
}

class AiStreamDone extends AiStreamEvent {
  final String model;
  final int tokensIn;
  final int tokensOut;
  final double costUsd;
  final String? finishReason;
  const AiStreamDone({required this.model, required this.tokensIn, required this.tokensOut, required this.costUsd, this.finishReason});
}

/// A failure, before or during the stream. The stream ends after it.
class AiStreamError extends AiStreamEvent {
  final String message;
  final String? code;
  final int? statusCode;
  const AiStreamError(this.message, {this.code, this.statusCode});
}

class AiEmbedResult {
  final String model;
  final String provider;
  final int dimensions;
  final List<List<double>> embeddings;

  const AiEmbedResult({required this.model, required this.provider, required this.dimensions, required this.embeddings});
}

/// AI Gateway: chat, streaming and embeddings through the project's own
/// provider keys (Studio → Project Settings → AI). Calls need a signed-in user
/// or a service-role key.
///
/// ```dart
/// final r = await client.ai.chat(messages: [AiMessage.user('Hi')]);
/// await for (final ev in client.ai.chatStream(messages: history)) {
///   if (ev is AiTextDelta) setState(() => reply += ev.text);
/// }
/// ```
class OrbitNestAi {
  final OrbitNestHttpClient _httpClient;
  final String _projectSlug;

  OrbitNestAi({required OrbitNestHttpClient httpClient, required String projectSlug})
      : _httpClient = httpClient,
        _projectSlug = projectSlug;

  String _path(String p) => '/api/project/$_projectSlug/ai/v1/$p';

  // Model replies outlast the default timeout, and a resend would pay twice.
  static final _options = Options(receiveTimeout: const Duration(seconds: 130), extra: {'noRetry': true});

  Map<String, dynamic> _body({
    required List<AiMessage> messages,
    String? model,
    String? provider,
    double? temperature,
    int? maxTokens,
    List<AiTool>? tools,
    Object? toolChoice,
    required bool stream,
  }) =>
      {
        if (model != null) 'model': model,
        if (provider != null) 'provider': provider,
        'messages': messages.map((m) => m.toJson()).toList(),
        if (temperature != null) 'temperature': temperature,
        if (maxTokens != null) 'max_tokens': maxTokens,
        if (tools != null) 'tools': tools.map((t) => t.toJson()).toList(),
        // 'auto' | 'none' | 'required', or a tool name to force that tool.
        if (toolChoice != null) 'tool_choice': toolChoice is String && !const ['auto', 'none', 'required'].contains(toolChoice) ? {'name': toolChoice} : toolChoice,
        'stream': stream,
      };

  /// One reply. Throws [AiException].
  Future<AiChatResult> chat({
    required List<AiMessage> messages,
    String? model,
    String? provider,
    double? temperature,
    int? maxTokens,
    List<AiTool>? tools,
    String? toolChoice,
  }) async {
    try {
      final res = await _httpClient.post(
        _path('chat'),
        data: _body(messages: messages, model: model, provider: provider, temperature: temperature, maxTokens: maxTokens, tools: tools, toolChoice: toolChoice, stream: false),
        options: _options,
      );
      return AiChatResult.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw await AiException.fromError(e);
    }
  }

  /// Streamed reply: [AiTextDelta] and [AiToolCallEvent]s, then one
  /// [AiStreamDone] — or an [AiStreamError], never a thrown error. Cancelling
  /// the subscription cancels the request.
  Stream<AiStreamEvent> chatStream({
    required List<AiMessage> messages,
    String? model,
    String? provider,
    double? temperature,
    int? maxTokens,
    List<AiTool>? tools,
    String? toolChoice,
  }) async* {
    // dart:io, not Dio: cancelling a Dio stream drains the rest of the body (the
    // server keeps generating and billing). A per-stream client closed with
    // force destroys the socket, which stops the reply at the server.
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    var closed = false;
    try {
      final HttpClientResponse res;
      try {
        final req = await client.postUrl(Uri.parse('${_httpClient.baseUrl}${_path('chat')}'));
        (await _httpClient.authHeaders()).forEach(req.headers.set);
        req.headers
          ..contentType = ContentType.json
          ..set(HttpHeaders.acceptHeader, 'text/event-stream');
        req.followRedirects = false;
        req.add(utf8.encode(jsonEncode(_body(
          messages: messages, model: model, provider: provider, temperature: temperature,
          maxTokens: maxTokens, tools: tools, toolChoice: toolChoice, stream: true,
        ))));
        res = await req.close().timeout(const Duration(seconds: 130));
      } catch (e) {
        yield AiStreamError('Network error: $e', code: 'NETWORK_ERROR');
        return;
      }
      if (res.statusCode != 200) {
        Map<String, dynamic>? body;
        try {
          body = Map<String, dynamic>.from(jsonDecode(await utf8.decodeStream(res)) as Map);
        } catch (_) {}
        final m = body?['message'];
        yield AiStreamError(m is List ? m.join(', ') : m?.toString() ?? 'Request failed (${res.statusCode})',
            code: body?['code']?.toString(), statusCode: res.statusCode);
        return;
      }
      try {
        await for (final line in res.transform(utf8.decoder).transform(const LineSplitter())) {
          if (!line.startsWith('data:')) continue;
          yield AiStreamEvent.fromJson(Map<String, dynamic>.from(jsonDecode(line.substring(5).trim()) as Map));
        }
      } catch (e) {
        if (!closed) yield AiStreamError('Stream interrupted: $e', code: 'STREAM_ERROR');
      }
    } finally {
      // Also runs when the listener cancels.
      closed = true;
      client.close(force: true);
    }
  }

  /// 768-dimension vectors, one per input (up to 100). Throws [AiException].
  Future<AiEmbedResult> embed(List<String> inputs, {String? model, String? provider}) async {
    try {
      final res = await _httpClient.post(
        _path('embeddings'),
        data: {'input': inputs, if (model != null) 'model': model, if (provider != null) 'provider': provider},
        options: _options,
      );
      final j = Map<String, dynamic>.from(res.data as Map);
      return AiEmbedResult(
        model: j['model'] as String,
        provider: j['provider'] as String,
        dimensions: (j['dimensions'] as num).toInt(),
        embeddings: (j['embeddings'] as List).map((v) => (v as List).map((x) => (x as num).toDouble()).toList()).toList(),
      );
    } catch (e) {
      throw await AiException.fromError(e);
    }
  }

  /// Models the project's saved keys can reach: `{id, provider, kind, default?}`.
  Future<List<Map<String, dynamic>>> models() async {
    try {
      final res = await _httpClient.get(_path('models'));
      return (res.data as List).map((m) => Map<String, dynamic>.from(m as Map)).toList();
    } catch (e) {
      throw await AiException.fromError(e);
    }
  }
}
