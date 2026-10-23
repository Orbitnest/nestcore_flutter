// Typed results of the AI data APIs: memory, collections, threads, traces.
// Rows come back as stored (snake_case); every row model keeps the full
// decoded map in `raw` for fields added after this SDK version.
import 'orbitnest_ai.dart' show AiToolCall;

double? _dbl(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
int? _intOrNull(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
int _int(Object? v, [int fallback = 0]) => _intOrNull(v) ?? fallback;
DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? v) =>
    v is List ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const [];
String? _str(Object? v) => v?.toString();

// ── Memory ────────────────────────────────────────────────────────────────

/// One remembered fact about a subject (`user:<id>`, `agent:support`, …).
class AiMemory {
  final String id;
  final String subjectType;
  final String subjectId;

  /// `fact`, `preference`, `episode`, `summary`, or your own word.
  final String kind;
  final String content;
  final String? embedModel;

  /// 1–5.
  final int importance;
  final Map<String, dynamic> metadata;
  final String? sourceThreadId;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Map<String, dynamic> raw;

  const AiMemory({
    required this.id,
    required this.subjectType,
    required this.subjectId,
    required this.kind,
    required this.content,
    this.embedModel,
    this.importance = 3,
    this.metadata = const {},
    this.sourceThreadId,
    this.expiresAt,
    this.createdAt,
    this.updatedAt,
    this.raw = const {},
  });

  /// `type:id`, the form `subject` parameters take.
  String get subject => '$subjectType:$subjectId';

  factory AiMemory.fromJson(Map<String, dynamic> j) => AiMemory(
        id: j['id'] as String,
        subjectType: _str(j['subject_type']) ?? '',
        subjectId: _str(j['subject_id']) ?? '',
        kind: _str(j['kind']) ?? 'fact',
        content: _str(j['content']) ?? '',
        embedModel: _str(j['embed_model']),
        importance: _int(j['importance'], 3),
        metadata: _map(j['metadata']),
        sourceThreadId: _str(j['source_thread_id']),
        expiresAt: _date(j['expires_at']),
        createdAt: _date(j['created_at']),
        updatedAt: _date(j['updated_at']),
        raw: j,
      );
}

/// A memory search hit.
class AiMemoryMatch {
  final AiMemory memory;

  /// Cosine similarity; null when the keyword fallback answered.
  final double? similarity;

  /// Similarity nudged by importance and recency; results are sorted by it.
  final double score;

  const AiMemoryMatch({required this.memory, this.similarity, required this.score});

  factory AiMemoryMatch.fromJson(Map<String, dynamic> j) =>
      AiMemoryMatch(memory: AiMemory.fromJson(j), similarity: _dbl(j['similarity']), score: _dbl(j['score']) ?? 0);
}

class AiMemoryAddResult {
  final AiMemory memory;

  /// True when a near-identical memory (cosine ≥ 0.92) was updated instead.
  final bool deduped;
  const AiMemoryAddResult({required this.memory, required this.deduped});

  factory AiMemoryAddResult.fromJson(Map<String, dynamic> j) =>
      AiMemoryAddResult(memory: AiMemory.fromJson(_map(j['memory'])), deduped: j['deduped'] == true);
}

class AiMemorySearchResult {
  final List<AiMemoryMatch> results;

  /// True when the model provider was down and keyword search answered.
  final bool degraded;
  final String? model;
  final int tokensIn;
  final double costUsd;

  const AiMemorySearchResult({required this.results, required this.degraded, this.model, this.tokensIn = 0, this.costUsd = 0});

  factory AiMemorySearchResult.fromJson(Map<String, dynamic> j) {
    final usage = _map(j['usage']);
    return AiMemorySearchResult(
      results: _maps(j['results']).map(AiMemoryMatch.fromJson).toList(),
      degraded: j['degraded'] == true,
      model: _str(j['model']),
      tokensIn: _int(usage['tokensIn']),
      costUsd: _dbl(usage['costUsd']) ?? 0,
    );
  }
}

class AiMemoryPage {
  final List<AiMemory> memories;
  final int total;
  const AiMemoryPage({required this.memories, required this.total});

  factory AiMemoryPage.fromJson(Map<String, dynamic> j) =>
      AiMemoryPage(memories: _maps(j['memories']).map(AiMemory.fromJson).toList(), total: _int(j['total']));
}

class AiMemorySubject {
  /// `type:id`.
  final String subject;
  final String subjectType;
  final String subjectId;
  final int memories;
  final DateTime? lastUpdated;
  const AiMemorySubject({required this.subject, required this.subjectType, required this.subjectId, required this.memories, this.lastUpdated});

  factory AiMemorySubject.fromJson(Map<String, dynamic> j) => AiMemorySubject(
        subject: _str(j['subject']) ?? '${j['subject_type']}:${j['subject_id']}',
        subjectType: _str(j['subject_type']) ?? '',
        subjectId: _str(j['subject_id']) ?? '',
        memories: _int(j['memories']),
        lastUpdated: _date(j['last_updated']),
      );
}

class AiReembedResult {
  final int reembedded;
  final int remaining;
  final String? model;
  const AiReembedResult({required this.reembedded, required this.remaining, this.model});

  factory AiReembedResult.fromJson(Map<String, dynamic> j) =>
      AiReembedResult(reembedded: _int(j['reembedded']), remaining: _int(j['remaining']), model: _str(j['model']));
}

// ── Collections ───────────────────────────────────────────────────────────

class AiCollection {
  final String id;
  final String name;
  final String? embedModel;
  final String? embedProvider;
  final int chunkTokens;
  final int chunkOverlap;

  /// Signed-in users may add documents only they can read.
  final bool userIngest;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;

  /// Set by `collections.list()`.
  final int? documents;

  /// Documents still `queued` or `processing` (set by `collections.list()`).
  final int? pending;
  final Map<String, dynamic> raw;

  const AiCollection({
    required this.id,
    required this.name,
    this.embedModel,
    this.embedProvider,
    this.chunkTokens = 400,
    this.chunkOverlap = 60,
    this.userIngest = false,
    this.metadata = const {},
    this.createdAt,
    this.documents,
    this.pending,
    this.raw = const {},
  });

  factory AiCollection.fromJson(Map<String, dynamic> j) => AiCollection(
        id: j['id'] as String,
        name: _str(j['name']) ?? '',
        embedModel: _str(j['embed_model']),
        embedProvider: _str(j['embed_provider']),
        chunkTokens: _int(j['chunk_tokens'], 400),
        chunkOverlap: _int(j['chunk_overlap'], 60),
        userIngest: j['user_ingest'] == true,
        metadata: _map(j['metadata']),
        createdAt: _date(j['created_at']),
        documents: _intOrNull(j['documents']),
        pending: _intOrNull(j['pending']),
        raw: j,
      );
}

/// Where a document's text comes from.
class AiDocumentSource {
  final Map<String, dynamic> _json;
  const AiDocumentSource._(this._json);

  /// Inline text (up to 5 MB).
  AiDocumentSource.text(String text) : this._({'text': text});

  /// A public http(s) URL: HTML, PDF or text.
  AiDocumentSource.url(String url) : this._({'url': url});

  /// A file in project storage: PDF, HTML or text, up to 50 MB.
  AiDocumentSource.storage({required String bucket, required String path})
      : this._({
          'storage': {'bucket': bucket, 'path': path}
        });

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(_json);
}

class AiDocument {
  final String id;
  final String collectionId;
  final String? ownerUserId;

  /// `text`, `storage` or `url`.
  final String sourceType;
  final String? sourceRef;
  final String? title;
  final Map<String, dynamic> metadata;

  /// `queued`, `processing`, `ready` or `failed`.
  final String status;
  final String? error;
  final int chunkCount;
  final int bytes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Map<String, dynamic> raw;

  const AiDocument({
    required this.id,
    required this.collectionId,
    this.ownerUserId,
    required this.sourceType,
    this.sourceRef,
    this.title,
    this.metadata = const {},
    required this.status,
    this.error,
    this.chunkCount = 0,
    this.bytes = 0,
    this.createdAt,
    this.updatedAt,
    this.raw = const {},
  });

  bool get isReady => status == 'ready';
  bool get isFailed => status == 'failed';

  /// `ready` or `failed`: ingestion has finished.
  bool get isDone => isReady || isFailed;

  factory AiDocument.fromJson(Map<String, dynamic> j) => AiDocument(
        id: j['id'] as String,
        collectionId: _str(j['collection_id']) ?? '',
        ownerUserId: _str(j['owner_user_id']),
        sourceType: _str(j['source_type']) ?? '',
        sourceRef: _str(j['source_ref']),
        title: _str(j['title']),
        metadata: _map(j['metadata']),
        status: _str(j['status']) ?? 'queued',
        error: _str(j['error']),
        chunkCount: _int(j['chunk_count']),
        bytes: _int(j['bytes']),
        createdAt: _date(j['created_at']),
        updatedAt: _date(j['updated_at']),
        raw: j,
      );
}

class AiDocumentPage {
  final List<AiDocument> documents;
  final int total;
  const AiDocumentPage({required this.documents, required this.total});

  factory AiDocumentPage.fromJson(Map<String, dynamic> j) =>
      AiDocumentPage(documents: _maps(j['documents']).map(AiDocument.fromJson).toList(), total: _int(j['total']));
}

class AiChunk {
  final String id;
  final int ordinal;
  final String content;
  final Map<String, dynamic> metadata;
  const AiChunk({required this.id, required this.ordinal, required this.content, this.metadata = const {}});

  factory AiChunk.fromJson(Map<String, dynamic> j) =>
      AiChunk(id: _str(j['id']) ?? '', ordinal: _int(j['ordinal']), content: _str(j['content']) ?? '', metadata: _map(j['metadata']));
}

/// The document a search hit came from.
class AiSearchDocument {
  final String id;
  final String? title;
  final String sourceType;
  final String? sourceRef;
  final Map<String, dynamic> metadata;
  const AiSearchDocument({required this.id, this.title, required this.sourceType, this.sourceRef, this.metadata = const {}});

  factory AiSearchDocument.fromJson(Map<String, dynamic> j) => AiSearchDocument(
        id: _str(j['id']) ?? '',
        title: _str(j['title']),
        sourceType: _str(j['sourceType']) ?? '',
        sourceRef: _str(j['sourceRef']),
        metadata: _map(j['metadata']),
      );
}

class AiSearchResult {
  /// Reciprocal-rank-fusion score (vector + keyword); results are sorted by it.
  final double score;
  final double? similarity;
  final bool keywordMatch;

  /// The best-matching words, wrapped in `**`.
  final String highlight;
  final AiChunk chunk;
  final AiSearchDocument document;

  const AiSearchResult({
    required this.score,
    this.similarity,
    required this.keywordMatch,
    required this.highlight,
    required this.chunk,
    required this.document,
  });

  factory AiSearchResult.fromJson(Map<String, dynamic> j) => AiSearchResult(
        score: _dbl(j['score']) ?? 0,
        similarity: _dbl(j['similarity']),
        keywordMatch: j['keywordMatch'] == true,
        highlight: _str(j['highlight']) ?? '',
        chunk: AiChunk.fromJson(_map(j['chunk'])),
        document: AiSearchDocument.fromJson(_map(j['document'])),
      );
}

class AiCollectionSearch {
  final List<AiSearchResult> results;
  final String? model;
  const AiCollectionSearch({required this.results, this.model});

  factory AiCollectionSearch.fromJson(Map<String, dynamic> j) =>
      AiCollectionSearch(results: _maps(j['results']).map(AiSearchResult.fromJson).toList(), model: _str(j['model']));
}

class AiCollectionStats {
  final int chunks;

  /// Chunks embedded with the collection's current model (re-embed progress).
  final int currentModelChunks;
  final int documents;
  final int failed;
  final String? model;
  const AiCollectionStats({required this.chunks, required this.currentModelChunks, required this.documents, required this.failed, this.model});

  factory AiCollectionStats.fromJson(Map<String, dynamic> j) => AiCollectionStats(
        chunks: _int(j['chunks']),
        currentModelChunks: _int(j['current_model_chunks']),
        documents: _int(j['documents']),
        failed: _int(j['failed']),
        model: _str(j['model']),
      );
}

// ── Threads ───────────────────────────────────────────────────────────────

class AiThread {
  final String id;
  final String? ownerUserId;
  final String? title;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Message count (set by `threads.list()`).
  final int? messages;

  /// Total cost of the thread (set by `threads.list()`).
  final double? costUsd;
  final Map<String, dynamic> raw;

  const AiThread({
    required this.id,
    this.ownerUserId,
    this.title,
    this.metadata = const {},
    this.createdAt,
    this.updatedAt,
    this.messages,
    this.costUsd,
    this.raw = const {},
  });

  factory AiThread.fromJson(Map<String, dynamic> j) => AiThread(
        id: j['id'] as String,
        ownerUserId: _str(j['owner_user_id']),
        title: _str(j['title']),
        metadata: _map(j['metadata']),
        createdAt: _date(j['created_at']),
        updatedAt: _date(j['updated_at']),
        messages: _intOrNull(j['messages']),
        costUsd: _dbl(j['cost_usd']),
        raw: j,
      );
}

class AiThreadPage {
  final List<AiThread> threads;
  final int total;
  const AiThreadPage({required this.threads, required this.total});

  factory AiThreadPage.fromJson(Map<String, dynamic> j) =>
      AiThreadPage(threads: _maps(j['threads']).map(AiThread.fromJson).toList(), total: _int(j['total']));
}

/// One part of a thread message: text, an image URL (data: or https), or an
/// image in project storage (read under the caller's storage policies).
class AiThreadPart {
  /// `text` or `image`.
  final String type;
  final String? text;
  final String? url;
  final String? bucket;
  final String? path;

  const AiThreadPart.text(String this.text)
      : type = 'text',
        url = null,
        bucket = null,
        path = null;

  const AiThreadPart.image(String this.url)
      : type = 'image',
        text = null,
        bucket = null,
        path = null;

  const AiThreadPart.storage({required String this.bucket, required String this.path})
      : type = 'image',
        text = null,
        url = null;

  const AiThreadPart._(this.type, this.text, this.url, this.bucket, this.path);

  factory AiThreadPart.fromJson(Map<String, dynamic> j) {
    final storage = _map(j['storage']);
    return AiThreadPart._(_str(j['type']) ?? 'text', _str(j['text']), _str(j['url']), _str(storage['bucket']), _str(storage['path']));
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (text != null) 'text': text,
        if (url != null) 'url': url,
        if (bucket != null) 'storage': {'bucket': bucket, 'path': path},
      };
}

class AiThreadMessage {
  final String id;
  final String threadId;

  /// `system`, `user`, `assistant` or `tool`.
  final String role;
  final List<AiThreadPart> content;
  final String? model;
  final String? provider;
  final int? tokensIn;
  final int? tokensOut;
  final double? costUsd;

  /// `streaming` while a run writes it (partial text), `complete`, or
  /// `error` if the run failed.
  final String status;
  final String? error;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  const AiThreadMessage({
    required this.id,
    required this.threadId,
    required this.role,
    this.content = const [],
    this.model,
    this.provider,
    this.tokensIn,
    this.tokensOut,
    this.costUsd,
    this.status = 'complete',
    this.error,
    this.metadata = const {},
    this.createdAt,
    this.raw = const {},
  });

  /// The text parts joined.
  String get text => content.where((p) => p.type == 'text').map((p) => p.text ?? '').join();

  factory AiThreadMessage.fromJson(Map<String, dynamic> j) {
    final c = j['content'];
    return AiThreadMessage(
      id: j['id'] as String,
      threadId: _str(j['thread_id']) ?? '',
      role: _str(j['role']) ?? 'user',
      content: c is String ? [AiThreadPart.text(c)] : _maps(c).map(AiThreadPart.fromJson).toList(),
      model: _str(j['model']),
      provider: _str(j['provider']),
      tokensIn: _intOrNull(j['tokens_in']),
      tokensOut: _intOrNull(j['tokens_out']),
      costUsd: _dbl(j['cost_usd']),
      status: _str(j['status']) ?? 'complete',
      error: _str(j['error']),
      metadata: _map(j['metadata']),
      createdAt: _date(j['created_at']),
      raw: j,
    );
  }
}

/// A source the model was given; the reply cites it as `[index]`.
class AiCitation {
  final int index;
  final String collection;
  final String documentId;
  final String chunkId;
  final String? title;
  final String? sourceRef;
  final String snippet;
  final double score;

  const AiCitation({
    required this.index,
    required this.collection,
    required this.documentId,
    required this.chunkId,
    this.title,
    this.sourceRef,
    required this.snippet,
    required this.score,
  });

  factory AiCitation.fromJson(Map<String, dynamic> j) => AiCitation(
        index: _int(j['index']),
        collection: _str(j['collection']) ?? '',
        documentId: _str(j['documentId']) ?? '',
        chunkId: _str(j['chunkId']) ?? '',
        title: _str(j['title']),
        sourceRef: _str(j['sourceRef']),
        snippet: _str(j['snippet']) ?? '',
        score: _dbl(j['score']) ?? 0,
      );
}

/// Built-in tools a thread run may give the model.
enum AiThreadTool {
  memorySearch('memory_search'),
  collectionsSearch('collections_search');

  final String wireName;
  const AiThreadTool(this.wireName);
}

/// Events of `AiThreadRef.run`: [ThreadRunMessage] first, then
/// [ThreadRunCitation]s, [ThreadRunDelta]s and tool events, then one
/// [ThreadRunDone] — or a [ThreadRunError], never a thrown error.
sealed class ThreadRunEvent {
  const ThreadRunEvent();

  /// Null for an event type this SDK version does not know (skipped).
  static ThreadRunEvent? fromJson(Map<String, dynamic> j) => switch (j['type']) {
        'message' => ThreadRunMessage(threadId: _str(j['threadId']) ?? '', messageId: _str(j['messageId']) ?? ''),
        'citation' => ThreadRunCitation(AiCitation.fromJson(j)),
        'delta' => ThreadRunDelta(_str(j['text']) ?? ''),
        'tool_call' => ThreadRunToolCall(AiToolCall.fromJson(j)),
        'tool_result' => ThreadRunToolResult(id: _str(j['id']) ?? '', name: _str(j['name']) ?? '', result: j['result']),
        'done' => ThreadRunDone(ThreadRunUsage.fromJson(j), messageId: _str(j['messageId']) ?? ''),
        'error' => ThreadRunError(_str(j['message']) ?? 'Run failed', code: _str(j['code'])),
        _ => null,
      };
}

/// The id of the assistant message being written (saved as it streams).
class ThreadRunMessage extends ThreadRunEvent {
  final String threadId;
  final String messageId;
  const ThreadRunMessage({required this.threadId, required this.messageId});
}

class ThreadRunCitation extends ThreadRunEvent {
  final AiCitation citation;
  const ThreadRunCitation(this.citation);
}

class ThreadRunDelta extends ThreadRunEvent {
  final String text;
  const ThreadRunDelta(this.text);
}

/// The model called a built-in tool; its [ThreadRunToolResult] follows.
class ThreadRunToolCall extends ThreadRunEvent {
  final AiToolCall call;
  const ThreadRunToolCall(this.call);
}

class ThreadRunToolResult extends ThreadRunEvent {
  final String id;
  final String name;
  final Object? result;
  const ThreadRunToolResult({required this.id, required this.name, this.result});

  factory ThreadRunToolResult.fromJson(Map<String, dynamic> j) =>
      ThreadRunToolResult(id: _str(j['id']) ?? '', name: _str(j['name']) ?? '', result: j['result']);
}

class ThreadRunUsage {
  final String model;
  final String? provider;
  final int tokensIn;
  final int tokensOut;
  final double costUsd;
  const ThreadRunUsage({required this.model, this.provider, required this.tokensIn, required this.tokensOut, required this.costUsd});

  factory ThreadRunUsage.fromJson(Map<String, dynamic> j) => ThreadRunUsage(
        model: _str(j['model']) ?? '',
        provider: _str(j['provider']),
        tokensIn: _int(j['tokensIn']),
        tokensOut: _int(j['tokensOut']),
        costUsd: _dbl(j['costUsd']) ?? 0,
      );
}

class ThreadRunDone extends ThreadRunEvent {
  final String messageId;
  final ThreadRunUsage usage;
  const ThreadRunDone(this.usage, {required this.messageId});

  String get model => usage.model;
  String? get provider => usage.provider;
  int get tokensIn => usage.tokensIn;
  int get tokensOut => usage.tokensOut;
  double get costUsd => usage.costUsd;
}

/// A failure, before or during the run. The stream ends after it.
class ThreadRunError extends ThreadRunEvent {
  final String message;
  final String? code;
  final int? statusCode;
  const ThreadRunError(this.message, {this.code, this.statusCode});

  @override
  String toString() => 'ThreadRunError(${code ?? statusCode}): $message';
}

/// `runOnce()`: the finished assistant message.
class ThreadRunResult {
  final String? messageId;
  final String text;
  final List<AiCitation> citations;
  final List<ThreadRunToolResult> toolResults;

  /// Null when the run produced no `done` event.
  final ThreadRunUsage? usage;

  const ThreadRunResult({this.messageId, required this.text, this.citations = const [], this.toolResults = const [], this.usage});

  factory ThreadRunResult.fromJson(Map<String, dynamic> j) => ThreadRunResult(
        messageId: _str(j['messageId']),
        text: _str(j['text']) ?? '',
        citations: _maps(j['citations']).map(AiCitation.fromJson).toList(),
        toolResults: _maps(j['toolCalls']).map(ThreadRunToolResult.fromJson).toList(),
        usage: j['usage'] is Map ? ThreadRunUsage.fromJson(_map(j['usage'])) : null,
      );
}

// ── Traces ────────────────────────────────────────────────────────────────

/// One model call: who, which model, tokens, latency, cost, outcome.
class AiTrace {
  final String id;
  final String? requestId;
  final String? threadId;
  final String? caller;

  /// `chat` or `embed`.
  final String kind;
  final String? endUserId;
  final String provider;
  final String model;

  /// `byok` or `platform`.
  final String? keySource;
  final String? promptHash;
  final int tokensIn;
  final int tokensOut;
  final double? costUsd;
  final int latencyMs;

  /// `ok` or `error`.
  final String status;
  final String? error;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  const AiTrace({
    required this.id,
    this.requestId,
    this.threadId,
    this.caller,
    required this.kind,
    this.endUserId,
    required this.provider,
    required this.model,
    this.keySource,
    this.promptHash,
    this.tokensIn = 0,
    this.tokensOut = 0,
    this.costUsd,
    this.latencyMs = 0,
    required this.status,
    this.error,
    this.createdAt,
    this.raw = const {},
  });

  factory AiTrace.fromJson(Map<String, dynamic> j) => AiTrace(
        id: j['id'] as String,
        requestId: _str(j['request_id']),
        threadId: _str(j['thread_id']),
        caller: _str(j['caller']),
        kind: _str(j['kind']) ?? '',
        endUserId: _str(j['end_user_id']),
        provider: _str(j['provider']) ?? '',
        model: _str(j['model']) ?? '',
        keySource: _str(j['key_source']),
        promptHash: _str(j['prompt_hash']),
        tokensIn: _int(j['tokens_in']),
        tokensOut: _int(j['tokens_out']),
        costUsd: _dbl(j['cost_usd']),
        latencyMs: _int(j['latency_ms']),
        status: _str(j['status']) ?? '',
        error: _str(j['error']),
        createdAt: _date(j['created_at']),
        raw: j,
      );
}

class AiTracePage {
  final List<AiTrace> traces;
  final int total;

  /// How long the project's plan keeps traces.
  final int retentionDays;
  const AiTracePage({required this.traces, required this.total, required this.retentionDays});

  factory AiTracePage.fromJson(Map<String, dynamic> j) => AiTracePage(
        traces: _maps(j['traces']).map(AiTrace.fromJson).toList(),
        total: _int(j['total']),
        retentionDays: _int(j['retentionDays']),
      );
}
