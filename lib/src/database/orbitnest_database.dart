import 'dart:async';
import 'package:flutter/foundation.dart';
import 'bloc/database_bloc.dart';
import 'bloc/database_state.dart';
import 'models/postgrest_response.dart';
import 'models/semantic_response.dart';
import 'services/database_service.dart';
import 'services/query_builder.dart';

/// Database API: direct async CRUD helpers and a Supabase-style query builder.
///
/// Every call goes straight to [DatabaseService] and returns its own future,
/// so concurrent calls never wait on or receive each other's results.
/// Failures throw [DatabaseException]; unsupported usage throws
/// [UnsupportedError] / [ArgumentError] before any request is sent.
class OrbitNestDatabase extends ChangeNotifier {
  final DatabaseBloc _databaseBloc;
  final DatabaseService _service;
  late final StreamSubscription _stateSubscription;

  DatabaseState _currentState = const DatabaseInitialState();

  OrbitNestDatabase(this._databaseBloc, this._service) {
    _stateSubscription = _databaseBloc.stream.listen((state) {
      _currentState = state;
      notifyListeners();
    });
    _currentState = _databaseBloc.state;
  }

  /// State of the [DatabaseBloc]. Only reflects events you dispatch to the
  /// bloc yourself — the methods on this class do not go through it.
  DatabaseState get state => _currentState;

  /// Stream of [DatabaseBloc] states (see [state]).
  Stream<DatabaseState> get onStateChange => _databaseBloc.stream;

  /// Create a query builder for a table (Supabase-style).
  PostgrestQueryBuilder<Map<String, dynamic>> from(String table) {
    return PostgrestQueryBuilder<Map<String, dynamic>>(_service, table);
  }

  /// Select rows. [filters] are equality filters (a `null` value means
  /// `IS NULL`); [orderBy] takes one entry like `'created_at.desc'`;
  /// [columns] is a plain column list. A page holds at most 100 rows.
  Future<PostgrestResponse<Map<String, dynamic>>> select(
    String table, {
    String columns = '*',
    Map<String, dynamic>? filters,
    List<String>? orderBy,
    int? limit,
    int? offset,
  }) async {
    final order = DatabaseService.parseOrder(orderBy);
    return _service.executeQuery(
      table: table,
      select: columns,
      filters: filters?.entries
          .map((e) => DatabaseService.encodeFilter(e.key, 'eq', e.value))
          .toList(),
      orderBy: order?.column,
      ascending: order?.ascending ?? true,
      limit: limit,
      offset: offset,
    );
  }

  /// Vector similarity search (pgvector). Returns rows ordered by distance from
  /// [vector], closest first. Requires `CREATE EXTENSION vector` and a `vector`
  /// column. [metric]: `l2` (default, `<->`), `cosine` (`<=>`), or `ip` (`<#>`).
  ///
  /// ```dart
  /// final res = await db.vectorSearch('documents', 'embedding', queryEmbedding,
  ///     metric: 'cosine', limit: 5);
  /// ```
  Future<PostgrestResponse<Map<String, dynamic>>> vectorSearch(
    String table,
    String column,
    List<double> vector, {
    String columns = '*',
    String metric = 'l2',
    int limit = 10,
  }) async {
    final safe = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
    final cols = columns.trim() == '*'
        ? null
        : columns.split(',').map((c) => c.trim()).toList();
    if (!safe.hasMatch(table) ||
        !safe.hasMatch(column) ||
        (cols != null && !cols.every(safe.hasMatch))) {
      throw ArgumentError('vectorSearch: unsafe table/column identifier');
    }
    final op = metric == 'cosine'
        ? '<=>'
        : metric == 'ip'
            ? '<#>'
            : '<->';
    final select = cols == null ? '*' : cols.map((c) => '"$c"').join(', ');
    final sql =
        'SELECT $select FROM "$table" ORDER BY "$column" $op \$1::vector LIMIT ${limit.toInt()}';
    return _service.executeSql(sql: sql, parameters: ['[${vector.join(',')}]']);
  }

  /// Rows nearest to [query] by meaning, from a column embedded with automatic
  /// embeddings (Studio → AI → Embeddings). Runs under RLS as the signed-in
  /// user (the anon key alone gets 401). Each row carries `_similarity`
  /// (cosine) and `_score`. With [hybridColumn], keyword matches on that text
  /// column are blended in (reciprocal rank fusion). [k] is 1–100 (default 10).
  ///
  /// Usually reached through `from(table).eq(...).semantic(column, query)`.
  Future<SemanticResponse> semantic(
    String table,
    String column,
    String query, {
    int? k,
    List<SemanticFilter>? filters,
    String? hybridColumn,
    double? minSimilarity,
  }) {
    return _service.semantic(
      table: table,
      column: column,
      query: query,
      k: k,
      filters: filters,
      hybridColumn: hybridColumn,
      minSimilarity: minSimilarity,
    );
  }

  /// Insert one row; returns the inserted row. `upsert: true` throws
  /// [UnsupportedError] — the API has no upsert.
  Future<PostgrestResponse<Map<String, dynamic>>> insert(
    String table,
    Map<String, dynamic> values, {
    bool upsert = false,
  }) async {
    return _service.insert(table: table, values: values, upsert: upsert);
  }

  /// Update rows whose columns equal [filters] (AND). `count` is the number of
  /// rows updated; `data` is empty. Requires a signed-in user (RLS applies).
  Future<PostgrestResponse<Map<String, dynamic>>> update(
    String table,
    Map<String, dynamic> values, {
    required Map<String, dynamic> filters,
  }) async {
    return _service.updateWhere(table: table, values: values, match: filters);
  }

  /// Delete rows whose columns equal [filters] (AND). `count` is the number of
  /// rows deleted. Requires a signed-in user (RLS applies).
  Future<PostgrestResponse<Map<String, dynamic>>> delete(
    String table, {
    required Map<String, dynamic> filters,
  }) async {
    return _service.deleteWhere(table: table, match: filters);
  }

  /// Insert several rows (one request per row — not atomic). Returns the
  /// inserted rows.
  Future<PostgrestResponse<Map<String, dynamic>>> insertMany(
    String table,
    List<Map<String, dynamic>> values,
  ) async {
    return _service.bulkInsert(table: table, values: values);
  }

  /// Same as [update]: every row matching [filters] gets [values].
  Future<PostgrestResponse<Map<String, dynamic>>> updateMany(
    String table,
    Map<String, dynamic> values, {
    required Map<String, dynamic> filters,
  }) async {
    return _service.updateWhere(table: table, values: values, match: filters);
  }

  /// Same as [delete]: deletes every row matching [filters] (column = value, AND).
  Future<PostgrestResponse<Map<String, dynamic>>> deleteMany(
    String table, {
    required Map<String, dynamic> filters,
  }) async {
    return _service.deleteWhere(table: table, match: filters);
  }

  /// Execute raw SQL with `$1`, `$2`, … placeholders bound from [parameters].
  /// Returns the result rows; `count` is the number of rows affected. The anon
  /// key (with or without a user session) may run SELECT and INSERT only.
  Future<PostgrestResponse<Map<String, dynamic>>> sql(
    String query, {
    List<dynamic>? parameters,
  }) async {
    return _service.executeSql(sql: query, parameters: parameters);
  }

  @override
  void dispose() {
    _stateSubscription.cancel();
    super.dispose();
  }
}
