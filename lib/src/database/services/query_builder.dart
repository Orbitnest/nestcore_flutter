import '../models/postgrest_response.dart';
import 'database_service.dart';

/// Supabase-style query builder over the OrbitNest data API.
///
/// Filters must be added before the terminal call (`execute`, `insert`,
/// `update`, `upsert`, `delete`). The API supports `eq`, `neq`, `gt`, `gte`,
/// `lt`, `lte`, `like`, `ilike`, `in` and `is`, one sort column, and pages of
/// at most 100 rows. Unsupported filters throw [UnsupportedError] instead of
/// being silently ignored. `update()`/`delete()` accept equality filters only.
class PostgrestQueryBuilder<T> {
  final DatabaseService _databaseService;
  final String _table;
  String _select = '*';
  final List<({String column, String op, Object? value})> _filters = [];
  String? _orderBy;
  bool _ascending = true;
  int? _limit;
  int? _offset;

  PostgrestQueryBuilder(this._databaseService, this._table);

  PostgrestQueryBuilder<T> _add(String column, String op, Object? value) {
    DatabaseService.encodeFilter(column, op, value); // validate now, not at execute()
    _filters.add((column: column, op: op, value: value));
    return this;
  }

  static Never _unsupported(String method) => throw UnsupportedError(
      '$method() is not supported by the OrbitNest data API. '
      'Use eq/neq/gt/gte/lt/lte/like/ilike/inFilter/isFilter, or database.sql().');

  /// Select columns (plain column list, applied client-side; `*` for all).
  PostgrestQueryBuilder<T> select([String? columns]) {
    _select = columns ?? '*';
    return this;
  }

  PostgrestQueryBuilder<T> eq(String column, dynamic value) => _add(column, 'eq', value);
  PostgrestQueryBuilder<T> neq(String column, dynamic value) => _add(column, 'neq', value);
  PostgrestQueryBuilder<T> gt(String column, dynamic value) => _add(column, 'gt', value);
  PostgrestQueryBuilder<T> gte(String column, dynamic value) => _add(column, 'gte', value);
  PostgrestQueryBuilder<T> lt(String column, dynamic value) => _add(column, 'lt', value);
  PostgrestQueryBuilder<T> lte(String column, dynamic value) => _add(column, 'lte', value);

  /// Like filter (case sensitive, `%` wildcards)
  PostgrestQueryBuilder<T> like(String column, String pattern) => _add(column, 'like', pattern);

  /// iLike filter (case insensitive)
  PostgrestQueryBuilder<T> ilike(String column, String pattern) => _add(column, 'ilike', pattern);

  /// Is filter — `null`, `true` or `false` only
  PostgrestQueryBuilder<T> isFilter(String column, dynamic value) =>
      _add(column, 'is', value ?? 'null');

  /// In filter
  PostgrestQueryBuilder<T> inFilter(String column, List<dynamic> values) =>
      _add(column, 'in', values);

  /// Match multiple columns (AND of equality filters)
  PostgrestQueryBuilder<T> match(Map<String, dynamic> query) {
    query.forEach((k, v) => _add(k, 'eq', v));
    return this;
  }

  /// Negation — only `not(column, 'eq', value)` (= `neq`) is supported.
  PostgrestQueryBuilder<T> not(String column, String operator, dynamic value) {
    if (operator == 'eq') return _add(column, 'neq', value);
    _unsupported('not($operator)');
  }

  PostgrestQueryBuilder<T> contains(String column, dynamic value) => _unsupported('contains');
  PostgrestQueryBuilder<T> containedBy(String column, dynamic value) => _unsupported('containedBy');
  PostgrestQueryBuilder<T> rangeLt(String column, String range) => _unsupported('rangeLt');
  PostgrestQueryBuilder<T> rangeGt(String column, String range) => _unsupported('rangeGt');
  PostgrestQueryBuilder<T> rangeGte(String column, String range) => _unsupported('rangeGte');
  PostgrestQueryBuilder<T> rangeLte(String column, String range) => _unsupported('rangeLte');
  PostgrestQueryBuilder<T> rangeAdjacent(String column, String range) => _unsupported('rangeAdjacent');
  PostgrestQueryBuilder<T> overlaps(String column, dynamic value) => _unsupported('overlaps');
  PostgrestQueryBuilder<T> textSearch(String column, String query, {String? config, String? type}) =>
      _unsupported('textSearch');
  PostgrestQueryBuilder<T> or(String filters) => _unsupported('or');
  PostgrestQueryBuilder<T> and(String filters) => _unsupported('and');

  /// Order by one column. [nullsFirst] is ignored (Postgres default ordering).
  PostgrestQueryBuilder<T> order(
    String column, {
    bool ascending = true,
    bool nullsFirst = false,
  }) {
    if (_orderBy != null) {
      throw UnsupportedError('The OrbitNest data API sorts by one column only');
    }
    _orderBy = column;
    _ascending = ascending;
    return this;
  }

  /// Limit the number of rows (the server caps a page at 100)
  PostgrestQueryBuilder<T> limit(int count, {int? foreignTable}) {
    _limit = count;
    return this;
  }

  /// Rows [from]..[to] inclusive (0-based)
  PostgrestQueryBuilder<T> range(int from, int to, {int? foreignTable}) {
    _offset = from;
    _limit = to - from + 1;
    return this;
  }

  /// Single row (limit 1)
  PostgrestQueryBuilder<T> single() => limit(1);

  /// Maybe single row (limit 1, no error when empty)
  PostgrestQueryBuilder<T> maybeSingle() => limit(1);

  /// Run the select.
  Future<PostgrestResponse<Map<String, dynamic>>> execute() async {
    return _databaseService.executeQuery(
      table: _table,
      select: _select,
      filters: _filters.map((f) => DatabaseService.encodeFilter(f.column, f.op, f.value)).toList(),
      orderBy: _orderBy,
      ascending: _ascending,
      limit: _limit,
      offset: _offset,
    );
  }

  /// Insert one row (Map) or several rows (List of Maps, one request each).
  /// [upsert], [onConflict] and [ignoreDuplicates] are not supported by the
  /// API: `upsert: true` throws [UnsupportedError].
  Future<PostgrestResponse<Map<String, dynamic>>> insert(
    dynamic values, {
    bool upsert = false,
    String? onConflict,
    bool ignoreDuplicates = false,
  }) async {
    if (upsert || ignoreDuplicates) throw DatabaseService.upsertUnsupported();
    if (values is Map<String, dynamic>) {
      return _databaseService.insert(table: _table, values: values);
    }
    if (values is List && values.every((v) => v is Map<String, dynamic>)) {
      return _databaseService.bulkInsert(
          table: _table, values: values.cast<Map<String, dynamic>>());
    }
    throw ArgumentError('Insert values must be a Map<String, dynamic> or a List of them');
  }

  /// Update the rows matched by the equality filters added before this call.
  Future<PostgrestResponse<Map<String, dynamic>>> update(Map<String, dynamic> values) async {
    return _databaseService.updateWhere(table: _table, values: values, match: _equalityMatch('update'));
  }

  /// Not supported by the API — always throws [UnsupportedError].
  Future<PostgrestResponse<Map<String, dynamic>>> upsert(
    dynamic values, {
    String? onConflict,
    bool ignoreDuplicates = false,
  }) async {
    throw DatabaseService.upsertUnsupported();
  }

  /// Delete the rows matched by the equality filters added before this call.
  Future<PostgrestResponse<Map<String, dynamic>>> delete() async {
    return _databaseService.deleteWhere(table: _table, match: _equalityMatch('delete'));
  }

  Map<String, dynamic> _equalityMatch(String action) {
    if (_filters.any((f) => f.op != 'eq')) {
      throw UnsupportedError('$action() supports equality filters (eq/match) only');
    }
    return {for (final f in _filters) f.column: f.value};
  }
}

/// Extension to add convenient methods
extension PostgrestQueryBuilderX<T> on PostgrestQueryBuilder<T> {
  /// `column IS NULL`
  PostgrestQueryBuilder<T> isNull(String column) => isFilter(column, 'null');

  /// Not supported by the API (no `IS NOT NULL` filter) — throws.
  PostgrestQueryBuilder<T> isNotNull(String column) => not(column, 'is', 'null');
}
