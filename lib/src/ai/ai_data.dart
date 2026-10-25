// AI data APIs for app code: memory, collections and threads. Like the AI
// gateway they need a signed-in user (RLS + per-user scoping) or the
// service-role key; the anon key alone gets 401.
import 'dart:async';

import 'package:dio/dio.dart';

import '../client/http_client.dart';
import 'ai_data_models.dart';
import 'nestcore_ai.dart';
import 'sse.dart';

// Writes are never retried: a resend would add a second row or pay twice.
final _write = Options(extra: {'noRetry': true});
// Embedding and model calls outlast the default timeout.
final _billed = Options(receiveTimeout: const Duration(seconds: 130), extra: {'noRetry': true});

String _seg(String s) => Uri.encodeComponent(s);

Map<String, dynamic>? _query(Map<String, Object?> q) {
  final out = <String, dynamic>{
    for (final e in q.entries)
      if (e.value != null) e.key: '${e.value}',
  };
  return out.isEmpty ? null : out;
}

Map<String, dynamic> _asMap(Object? data) => Map<String, dynamic>.from(data as Map);

Future<T> _send<T>(Future<Response<dynamic>> Function() send, T Function(dynamic data) parse) async {
  final Response<dynamic> res;
  try {
    res = await send();
  } catch (e) {
    throw await AiException.fromError(e);
  }
  return parse(res.data);
}

Object _content(Object content) {
  if (content is String) return content;
  if (content is Iterable) {
    return content.map((p) {
      if (p is AiThreadPart) return p.toJson();
      if (p is AiContentPart) return p.toJson();
      if (p is Map) return Map<String, dynamic>.from(p);
      throw ArgumentError.value(p, 'content', 'parts must be AiThreadPart, AiContentPart or Map');
    }).toList();
  }
  throw ArgumentError.value(content, 'content', 'must be a String or a list of parts');
}

// ── Memory ────────────────────────────────────────────────────────────────

/// Memory API: facts about a user (or an agent, an org…) with semantic
/// search. A signed-in user reads and writes only their own memory; the
/// service key may name any `subject` (`type:id`, e.g. `user:<id>`).
///
/// ```dart
/// await client.memory.add('Prefers vegetarian recipes', kind: 'preference');
/// final hits = await client.memory.search('what should I cook?');
/// ```
///
/// Failures throw [AiException].
class NestCoreMemory {
  final NestCoreHttpClient _http;
  final String _slug;

  NestCoreMemory({required NestCoreHttpClient httpClient, required String projectSlug})
      : _http = httpClient,
        _slug = projectSlug;

  String _path([String p = '']) => '/api/project/$_slug/ai/v1/memory$p';

  /// Remember something. `deduped: true` means an existing near-identical
  /// memory (cosine ≥ 0.92) was updated instead; pass `dedupe: false` to
  /// always add. [importance] is 1–5 (default 3); after [expiresAt] the memory
  /// is deleted.
  Future<AiMemoryAddResult> add(
    String content, {
    String? subject,
    String? kind,
    int? importance,
    DateTime? expiresAt,
    Map<String, dynamic>? metadata,
    String? sourceThreadId,
    bool? dedupe,
  }) =>
      _send(
        () => _http.post(_path(), options: _billed, data: {
          'content': content,
          if (subject != null) 'subject': subject,
          if (kind != null) 'kind': kind,
          if (importance != null) 'importance': importance,
          if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
          if (metadata != null) 'metadata': metadata,
          if (sourceThreadId != null) 'sourceThreadId': sourceThreadId,
          if (dedupe != null) 'dedupe': dedupe,
        }),
        (d) => AiMemoryAddResult.fromJson(_asMap(d)),
      );

  /// The most relevant memories ([k] up to 50, default 5). `degraded: true`
  /// means the model provider was down and keyword search answered.
  Future<AiMemorySearchResult> search(String query, {String? subject, int? k, String? kind, double? minSimilarity}) => _send(
        () => _http.post(_path('/search'), options: _billed, data: {
          'query': query,
          if (subject != null) 'subject': subject,
          if (k != null) 'k': k,
          if (kind != null) 'kind': kind,
          if (minSimilarity != null) 'minSimilarity': minSimilarity,
        }),
        (d) => AiMemorySearchResult.fromJson(_asMap(d)),
      );

  /// A subject's memories, newest first.
  Future<AiMemoryPage> list({String? subject, String? kind, int? limit, int? offset}) => _send(
        () => _http.get(_path(), queryParameters: _query({'subject': subject, 'kind': kind, 'limit': limit, 'offset': offset})),
        (d) => AiMemoryPage.fromJson(_asMap(d)),
      );

  Future<AiMemory> get(String id) => _send(() => _http.get(_path('/${_seg(id)}')), (d) => AiMemory.fromJson(_asMap(d)));

  /// Change a memory. [clearExpiresAt] removes its expiry.
  Future<AiMemory> update(
    String id, {
    String? content,
    String? kind,
    int? importance,
    DateTime? expiresAt,
    bool clearExpiresAt = false,
    Map<String, dynamic>? metadata,
  }) =>
      _send(
        () => _http.patch(_path('/${_seg(id)}'), options: _billed, data: {
          if (content != null) 'content': content,
          if (kind != null) 'kind': kind,
          if (importance != null) 'importance': importance,
          if (clearExpiresAt) 'expiresAt': null else if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
          if (metadata != null) 'metadata': metadata,
        }),
        (d) => AiMemory.fromJson(_asMap(d)),
      );

  /// Delete one memory. False when it did not exist (or is not yours).
  Future<bool> remove(String id) =>
      _send(() => _http.delete(_path('/${_seg(id)}'), options: _write), (d) => _asMap(d)['deleted'] == true);

  /// Delete every memory of a subject (rows and vectors); returns how many.
  /// A signed-in user always forgets themselves.
  Future<int> forget({String? subject}) => _send(
        () => _http.post(_path('/forget'), options: _write, data: {if (subject != null) 'subject': subject}),
        (d) => (_asMap(d)['deleted'] as num?)?.toInt() ?? 0,
      );

  /// Service key: subjects that have memories.
  Future<List<AiMemorySubject>> subjects({String? type, int? limit}) => _send(
        () => _http.get(_path('/subjects'), queryParameters: _query({'type': type, 'limit': limit})),
        (d) => (d as List).map((m) => AiMemorySubject.fromJson(_asMap(m))).toList(),
      );

  /// Service key: re-embed memories made with another model (after a
  /// provider change), up to 64 per call.
  Future<AiReembedResult> reembed({String? subject, int? limit}) => _send(
        () => _http.post(_path('/reembed'), options: _billed, data: {
          if (subject != null) 'subject': subject,
          if (limit != null) 'limit': limit,
        }),
        (d) => AiReembedResult.fromJson(_asMap(d)),
      );
}

// ── Collections ───────────────────────────────────────────────────────────

/// Vector collections: documents chunked, embedded and searched with hybrid
/// (vector + keyword) retrieval under RLS. Creating collections and adding
/// shared documents needs the service key; a collection with `userIngest`
/// lets signed-in users add documents only they can read.
///
/// ```dart
/// final kb = client.collections.from('handbook');
/// await kb.ingest(AiDocumentSource.text(notes), title: 'Notes', wait: true);
/// final hits = await kb.search('How do refunds work?');
/// ```
///
/// Failures throw [AiException].
class NestCoreCollections {
  final NestCoreHttpClient _http;
  final String _slug;

  NestCoreCollections({required NestCoreHttpClient httpClient, required String projectSlug})
      : _http = httpClient,
        _slug = projectSlug;

  String _path([String p = '']) => '/api/project/$_slug/ai/v1/collections$p';

  /// One collection's documents and search.
  AiCollectionRef from(String name) => AiCollectionRef._(_http, _slug, name);

  /// Service key. [name] is `[a-z0-9][a-z0-9_-]{0,62}`; [model] defaults to the
  /// project's embedding default (fixed by the first document).
  Future<AiCollection> create({
    required String name,
    String? model,
    String? provider,
    int? chunkTokens,
    int? chunkOverlap,
    bool? userIngest,
    Map<String, dynamic>? metadata,
  }) =>
      _send(
        () => _http.post(_path(), options: _write, data: {
          'name': name,
          if (model != null) 'model': model,
          if (provider != null) 'provider': provider,
          if (chunkTokens != null) 'chunkTokens': chunkTokens,
          if (chunkOverlap != null) 'chunkOverlap': chunkOverlap,
          if (userIngest != null) 'userIngest': userIngest,
          if (metadata != null) 'metadata': metadata,
        }),
        (d) => AiCollection.fromJson(_asMap(d)),
      );

  /// Every collection, with document and pending counts.
  Future<List<AiCollection>> list() =>
      _send(() => _http.get(_path()), (d) => (d as List).map((c) => AiCollection.fromJson(_asMap(c))).toList());

  Future<AiCollection> get(String name) => _send(() => _http.get(_path('/${_seg(name)}')), (d) => AiCollection.fromJson(_asMap(d)));

  /// Service key. Changing [model] re-embeds every chunk in the background.
  Future<AiCollection> update(String name, {bool? userIngest, Map<String, dynamic>? metadata, String? model, String? provider}) => _send(
        () => _http.patch(_path('/${_seg(name)}'), options: _write, data: {
          if (userIngest != null) 'userIngest': userIngest,
          if (metadata != null) 'metadata': metadata,
          if (model != null) 'model': model,
          if (provider != null) 'provider': provider,
        }),
        (d) => AiCollection.fromJson(_asMap(d)),
      );

  /// Service key: delete a collection with its documents and chunks.
  Future<bool> delete(String name) =>
      _send(() => _http.delete(_path('/${_seg(name)}'), options: _write), (d) => _asMap(d)['deleted'] == true);
}

/// One collection: `client.collections.from('handbook')`.
class AiCollectionRef {
  final NestCoreHttpClient _http;
  final String _slug;
  final String name;

  AiCollectionRef._(this._http, this._slug, this.name);

  String _path([String p = '']) => '/api/project/$_slug/ai/v1/collections/${_seg(name)}$p';

  /// Add a document; it is chunked and embedded in the background (PDF, HTML
  /// and text are read from storage or a URL). Returns it `queued`, or with
  /// [wait] polls until it is `ready` or `failed` (see [waitFor]).
  /// [ownerUserId] (service key only) makes the document readable by that
  /// user alone.
  Future<AiDocument> ingest(
    AiDocumentSource source, {
    String? title,
    Map<String, dynamic>? metadata,
    String? ownerUserId,
    bool wait = false,
    Duration timeout = const Duration(minutes: 2),
    Duration interval = const Duration(seconds: 1),
  }) async {
    final doc = await _send(
      () => _http.post(_path('/documents'), options: _write, data: {
        ...source.toJson(),
        if (title != null) 'title': title,
        if (metadata != null) 'metadata': metadata,
        if (ownerUserId != null) 'ownerUserId': ownerUserId,
      }),
      (d) => AiDocument.fromJson(_asMap(d)),
    );
    if (!wait || doc.isDone) return doc;
    return waitFor(doc.id, timeout: timeout, interval: interval);
  }

  /// Poll a document until it is `ready` or `failed`. Throws [AiException]
  /// with code `TIMEOUT` when [timeout] passes first.
  Future<AiDocument> waitFor(
    String documentId, {
    Duration timeout = const Duration(minutes: 2),
    Duration interval = const Duration(seconds: 1),
  }) async {
    final until = DateTime.now().add(timeout);
    for (;;) {
      final doc = await getDocument(documentId);
      if (doc.isDone) return doc;
      if (DateTime.now().isAfter(until)) {
        throw AiException('Document $documentId is still ${doc.status}', code: 'TIMEOUT');
      }
      await Future<void>.delayed(interval);
    }
  }

  /// Hybrid search (vector + keyword, reciprocal rank fusion); `hybrid: false`
  /// is vector only. [filter] matches documents whose metadata contains it.
  Future<AiCollectionSearch> search(String query, {int? k, bool? hybrid, Map<String, dynamic>? filter, double? minSimilarity}) => _send(
        () => _http.post(_path('/search'), options: _billed, data: {
          'query': query,
          if (k != null) 'k': k,
          if (hybrid != null) 'hybrid': hybrid,
          if (filter != null) 'filter': filter,
          if (minSimilarity != null) 'minSimilarity': minSimilarity,
        }),
        (d) => AiCollectionSearch.fromJson(_asMap(d)),
      );

  /// [status]: `queued`, `processing`, `ready` or `failed`.
  Future<AiDocumentPage> listDocuments({String? status, int? limit, int? offset}) => _send(
        () => _http.get(_path('/documents'), queryParameters: _query({'status': status, 'limit': limit, 'offset': offset})),
        (d) => AiDocumentPage.fromJson(_asMap(d)),
      );

  Future<AiDocument> getDocument(String id) =>
      _send(() => _http.get(_path('/documents/${_seg(id)}')), (d) => AiDocument.fromJson(_asMap(d)));

  /// Delete a document and its chunks. False when it did not exist or is not
  /// yours to delete.
  Future<bool> remove(String documentId) =>
      _send(() => _http.delete(_path('/documents/${_seg(documentId)}'), options: _write), (d) => _asMap(d)['deleted'] == true);

  Future<AiCollectionStats> stats() => _send(() => _http.get(_path('/stats')), (d) => AiCollectionStats.fromJson(_asMap(d)));
}

// ── Threads ───────────────────────────────────────────────────────────────

/// Threads: persistent conversations with per-message tokens and cost. A
/// signed-in user owns the threads they create; the service key can create
/// threads for any user (`ownerUserId`).
///
/// ```dart
/// final t = await client.ai.threads.create(title: 'Trip ideas');
/// await for (final ev in client.ai.threads.from(t.id).run(input: 'Plan a weekend in Oslo', memory: true)) {
///   if (ev is ThreadRunDelta) setState(() => reply += ev.text);
/// }
/// ```
///
/// Failures throw [AiException] (`run()` yields a [ThreadRunError] instead).
class AiThreads {
  final NestCoreHttpClient _http;
  final String _slug;

  AiThreads({required NestCoreHttpClient httpClient, required String projectSlug})
      : _http = httpClient,
        _slug = projectSlug;

  String _path([String p = '']) => '/api/project/$_slug/ai/v1/threads$p';

  AiThreadRef from(String id) => AiThreadRef._(_http, _slug, id);

  Future<AiThread> create({String? title, Map<String, dynamic>? metadata, String? ownerUserId}) => _send(
        () => _http.post(_path(), options: _write, data: {
          if (title != null) 'title': title,
          if (metadata != null) 'metadata': metadata,
          if (ownerUserId != null) 'ownerUserId': ownerUserId,
        }),
        (d) => AiThread.fromJson(_asMap(d)),
      );

  /// Newest first, with message counts and cost.
  Future<AiThreadPage> list({int? limit, int? offset, String? ownerUserId}) => _send(
        () => _http.get(_path(), queryParameters: _query({'limit': limit, 'offset': offset, 'ownerUserId': ownerUserId})),
        (d) => AiThreadPage.fromJson(_asMap(d)),
      );

  Future<AiThread> get(String id) => from(id).get();

  Future<bool> delete(String id) => from(id).delete();
}

/// One thread: `client.ai.threads.from(id)`.
class AiThreadRef {
  final NestCoreHttpClient _http;
  final String _slug;
  final String id;

  AiThreadRef._(this._http, this._slug, this.id);

  String _path([String p = '']) => '/api/project/$_slug/ai/v1/threads/${_seg(id)}$p';

  Future<AiThread> get() => _send(() => _http.get(_path()), (d) => AiThread.fromJson(_asMap(d)));

  /// [clearTitle] sets the title to null.
  Future<AiThread> update({String? title, bool clearTitle = false, Map<String, dynamic>? metadata}) => _send(
        () => _http.patch(_path(), options: _write, data: {
          if (clearTitle) 'title': null else if (title != null) 'title': title,
          if (metadata != null) 'metadata': metadata,
        }),
        (d) => AiThread.fromJson(_asMap(d)),
      );

  /// Delete the thread and its messages.
  Future<bool> delete() => _send(() => _http.delete(_path(), options: _write), (d) => _asMap(d)['deleted'] == true);

  /// Oldest first: the newest [limit], or those created after message [after]
  /// (resume after a reconnect).
  Future<List<AiThreadMessage>> messages({int? limit, String? after}) => _send(
        () => _http.get(_path('/messages'), queryParameters: _query({'limit': limit, 'after': after})),
        (d) => (d as List).map((m) => AiThreadMessage.fromJson(_asMap(m))).toList(),
      );

  /// Add a message without running the model. [content] is a String or a list
  /// of [AiThreadPart] / [AiContentPart]. Users may add `user` messages only.
  Future<AiThreadMessage> append(Object content, {String? role, Map<String, dynamic>? metadata}) async {
    final body = {
      'content': _content(content),
      if (role != null) 'role': role,
      if (metadata != null) 'metadata': metadata,
    };
    return _send(() => _http.post(_path('/messages'), options: _write, data: body), (d) => AiThreadMessage.fromJson(_asMap(d)));
  }

  Map<String, dynamic> _runBody({
    Object? input,
    String? model,
    String? provider,
    String? system,
    double? temperature,
    int? maxTokens,
    Object? memory,
    List<String>? collections,
    List<AiThreadTool>? tools,
    int? maxContextTokens,
    required bool stream,
  }) {
    if (memory != null && memory is! bool && memory is! String) {
      throw ArgumentError.value(memory, 'memory', 'must be a bool or a "type:id" subject');
    }
    return {
      if (input != null) 'input': _content(input),
      if (model != null) 'model': model,
      if (provider != null) 'provider': provider,
      if (system != null) 'system': system,
      if (temperature != null) 'temperature': temperature,
      if (maxTokens != null) 'maxTokens': maxTokens,
      if (memory != null) 'memory': memory,
      if (collections != null) 'collections': collections,
      if (tools != null) 'tools': tools.map((t) => t.wireName).toList(),
      if (maxContextTokens != null) 'maxContextTokens': maxContextTokens,
      'stream': stream,
    };
  }

  /// Stream the assistant's next message: [ThreadRunMessage] (its id),
  /// [ThreadRunCitation]s, [ThreadRunDelta]s, tool events, then
  /// [ThreadRunDone] — or a [ThreadRunError], never a thrown error.
  ///
  /// [input] (a String or parts) is appended as a user message first.
  /// [memory]: `true` gives the model the user's memories; with the service
  /// key a `type:id` subject. [collections] are searched for sources the model
  /// cites as `[n]`. [tools] are built-in tools the model may call.
  /// [maxContextTokens] is the history + context budget (default 8000).
  ///
  /// The reply is saved as it streams, so another device can read it with
  /// [messages] or on the realtime channel `broadcast:ai:thread:<id>`.
  /// Cancelling the subscription closes the connection and stops the run.
  Stream<ThreadRunEvent> run({
    Object? input,
    String? model,
    String? provider,
    String? system,
    double? temperature,
    int? maxTokens,
    Object? memory,
    List<String>? collections,
    List<AiThreadTool>? tools,
    int? maxContextTokens,
  }) async* {
    final Map<String, dynamic> body;
    try {
      body = _runBody(
        input: input, model: model, provider: provider, system: system, temperature: temperature, maxTokens: maxTokens,
        memory: memory, collections: collections, tools: tools, maxContextTokens: maxContextTokens, stream: true,
      );
    } on ArgumentError catch (e) {
      yield ThreadRunError(e.toString(), code: 'INVALID_ARGUMENT');
      return;
    }
    await for (final item in postSse(_http, _path('/run'), body)) {
      if (item is SseFailure) {
        yield ThreadRunError(item.message, code: item.code, statusCode: item.statusCode);
        continue;
      }
      final ev = ThreadRunEvent.fromJson(item as Map<String, dynamic>);
      if (ev != null) yield ev;
    }
  }

  /// Run and wait for the finished message (no streaming). Throws
  /// [AiException].
  Future<ThreadRunResult> runOnce({
    Object? input,
    String? model,
    String? provider,
    String? system,
    double? temperature,
    int? maxTokens,
    Object? memory,
    List<String>? collections,
    List<AiThreadTool>? tools,
    int? maxContextTokens,
  }) async {
    final body = _runBody(
      input: input, model: model, provider: provider, system: system, temperature: temperature, maxTokens: maxTokens,
      memory: memory, collections: collections, tools: tools, maxContextTokens: maxContextTokens, stream: false,
    );
    return _send(
      () => _http.post(_path('/run'), data: body, options: Options(receiveTimeout: const Duration(seconds: 180), extra: {'noRetry': true})),
      (d) => ThreadRunResult.fromJson(_asMap(d)),
    );
  }
}
