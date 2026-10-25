import '../models/postgrest_response.dart';
import '../models/semantic_response.dart';
import 'database_service.dart';

/// Supabase-style query builder over the NestCore data API.
///
/// Filters must be added before the terminal call (`execute`, `semantic`,
/// `insert`, `update`, `upsert`, `delete`). The API supports `eq`, `neq`,
/// `gt`, `gte`, `lt`, `lte`, `like`, `ilike`, `in` and `is`, one sort column,
/// and pages of at most 100 rows. `textSearch` and `nearest` chain like the
/// other filters; a query using them runs as one parameterized SELECT through
/// the SQL endpoint (values are bound, never interpolated; RLS applies).
/// Unsupported filters throw [UnsupportedError] instead of being silently
/// ignored. `update()`/`delete()` accept equality filters only.
class PostgrestQueryBuilder<T> {
  final DatabaseService _databaseService;
  final String _table;
  String _select = '*';
  final List<({String column, String op, Object? value})> _filters = [];
  String? _orderBy;
  bool _ascending = true;
  int? _limit;
  int? _offset;
  final List<({String column, String query, String config, String fn})> _textSearches = [];
  ({String column, String vector, String op})? _nearest;

  PostgrestQueryBuilder(this._databaseService, this._table);

  static final _ident = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  static String _checkIdent(String name, String what) {
    if (!_ident.hasMatch(name)) throw ArgumentError.value(name, what, 'Invalid identifier');
    return name;
  }

  PostgrestQueryBuilder<T> _add(String column, String op, Object? value) {
    DatabaseService.encodeFilter(column, op, value); // validate now, not at execute()
    _filters.add((column: column, op: op, value: value));
    return this;
  }

  static Never _unsupported(String method) => throw UnsupportedError(
      '$method() is not supported by the NestCore data API. '
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

  /// Full-text search: `to_tsvector(config, column) @@ <fn>(config, query)`.
  /// [type] picks the query parser: `websearch` (default — quotes, `or`, `-`),
  /// `plain` (all words) or `phrase` (words in order). [config] is the text
  /// search configuration (default `english`). Chains with the other filters.
  PostgrestQueryBuilder<T> textSearch(String column, String query, {String? config, String? type}) {
    _checkIdent(column, 'column');
    final cfg = _checkIdent(config ?? 'english', 'config');
    final fn = switch (type) {
      null || 'websearch' => 'websearch_to_tsquery',
      'plain' => 'plainto_tsquery',
      'phrase' => 'phraseto_tsquery',
      _ => throw ArgumentError.value(type, 'type', 'must be websearch, plain or phrase'),
    };
    _textSearches.add((column: column, query: query, config: cfg, fn: fn));
    return this;
  }

  /// Order by vector distance from [vector] (pgvector), nearest first.
  /// [metric]: `l2` (default, `<->`), `cosine` (`<=>`) or `ip` (`<#>`).
  /// Requires the `vector` extension and a `vector` column.
  PostgrestQueryBuilder<T> nearest(String column, List<num> vector, {String metric = 'l2', int? limit}) {
    _checkIdent(column, 'column');
    if (vector.isEmpty || vector.any((n) => !n.isFinite)) {
      throw ArgumentError.value(vector, 'vector', 'must be a non-empty list of finite numbers');
    }
    final op = switch (metric) {
      'l2' => '<->',
      'cosine' => '<=>',
      'ip' => '<#>',
      _ => throw ArgumentError.value(metric, 'metric', 'must be l2, cosine or ip'),
    };
    _nearest = (column: column, vector: '[${vector.join(',')}]', op: op);
    if (limit != null) _limit = limit;
    return this;
  }
  PostgrestQueryBuilder<T> or(String filters) => _unsupported('or');
  PostgrestQueryBuilder<T> and(String filters) => _unsupported('and');

  /// Order by one column. [nullsFirst] is ignored (Postgres default ordering).
  PostgrestQueryBuilder<T> order(
    String column, {
    bool ascending = true,
    bool nullsFirst = false,
  }) {
    if (_orderBy != null) {
      throw UnsupportedError('The NestCore data API sorts by one column only');
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

  /// Run the select. With `textSearch`/`nearest`, `count` is the number of
  /// rows returned (otherwise the total matching rows).
  Future<PostgrestResponse<Map<String, dynamic>>> execute() async {
    if (_textSearches.isNotEmpty || _nearest != null) {
      final (:sql, :params) = _buildSql();
      final res = await _databaseService.executeSql(sql: sql, parameters: params);
      return PostgrestResponse<Map<String, dynamic>>(data: res.data, count: res.data.length, status: res.status);
    }
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

  /// Semantic search over an embedded column ([column] is the vector column
  /// of automatic embeddings), keeping this builder's filters (`eq`, `gt`,
  /// `inFilter`, …). `limit()` sets [k] when [k] is not given. Each row carries
  /// `_similarity` and `_score`. Cannot be combined with `textSearch`,
  /// `nearest`, `order` or an offset (use [hybridColumn] for keyword ranking).
  /// Needs a signed-in user. Throws [DatabaseException] on failure.
  Future<SemanticResponse> semantic(String column, String query, {int? k, String? hybridColumn, double? minSimilarity}) async {
    _checkIdent(column, 'column');
    if (_textSearches.isNotEmpty || _nearest != null) {
      throw UnsupportedError('semantic() cannot be combined with textSearch() or nearest(); use hybridColumn for keyword ranking');
    }
    if (_orderBy != null || (_offset ?? 0) > 0) {
      throw UnsupportedError('semantic() orders by similarity and returns the top k: drop order() and the range offset');
    }
    final filters = [
      for (final f in _filters)
        if (f.op == 'is' || (f.op == 'eq' && f.value == null))
          SemanticFilter(f.column, 'is', _isValue(f.value))
        else
          SemanticFilter(f.column, f.op, f.value),
    ];
    final res = await _databaseService.semantic(
      table: _table,
      column: column,
      query: query,
      k: k ?? _limit,
      filters: filters,
      hybridColumn: hybridColumn,
      minSimilarity: minSimilarity,
    );
    final cols = _selectColumns();
    if (cols == null) return res;
    return SemanticResponse(
      model: res.model,
      rows: res.rows
          .map((r) => {
                for (final c in [...cols, '_similarity', '_score'])
                  if (r.containsKey(c)) c: r[c]
              })
          .toList(),
    );
  }

  /// `is` filter values (`null`/`true`/`false`, as values or strings).
  static Object? _isValue(Object? v) => switch ('$v'.toLowerCase()) {
        'true' => true,
        'false' => false,
        _ => null,
      };

  List<String>? _selectColumns() {
    final s = _select.trim();
    if (s.isEmpty || s == '*') return null;
    return s.split(',').map((c) => _checkIdent(c.trim(), 'select')).toList();
  }

  /// The SELECT for `textSearch`/`nearest` queries: identifiers checked and
  /// quoted, every value bound as `$n`.
  ({String sql, List<Object?> params}) _buildSql() {
    final params = <Object?>[];
    String bind(Object? v) {
      params.add(v);
      return '\$${params.length}';
    }

    String q(String id) => '"${_checkIdent(id, 'identifier')}"';
    final cols = _selectColumns();
    var sql = 'SELECT ${cols == null ? '*' : cols.map(q).join(', ')} FROM ${q(_table)}';

    final where = <String>[];
    for (final f in _filters) {
      final col = q(f.column);
      switch (f.op) {
        case 'is':
        case 'eq' when f.value == null:
          final v = _isValue(f.value);
          where.add('$col IS ${v == null ? 'NULL' : v == true ? 'TRUE' : 'FALSE'}');
        case 'eq':
          where.add('$col = ${bind(f.value)}');
        case 'neq':
          where.add('$col != ${bind(f.value)}');
        case 'gt':
          where.add('$col > ${bind(f.value)}');
        case 'gte':
          where.add('$col >= ${bind(f.value)}');
        case 'lt':
          where.add('$col < ${bind(f.value)}');
        case 'lte':
          where.add('$col <= ${bind(f.value)}');
        case 'like':
          where.add('$col::text LIKE ${bind(f.value)}');
        case 'ilike':
          where.add('$col::text ILIKE ${bind(f.value)}');
        case 'in':
          where.add('$col IN (${(f.value as Iterable).map(bind).join(', ')})');
        default:
          throw UnsupportedError('Filter operator "${f.op}"');
      }
    }
    for (final t in _textSearches) {
      // config is a checked identifier; the query is bound.
      where.add("to_tsvector('${t.config}', ${q(t.column)}::text) @@ ${t.fn}('${t.config}', ${bind(t.query)})");
    }
    if (where.isNotEmpty) sql += ' WHERE ${where.join(' AND ')}';

    final order = <String>[
      if (_nearest case final n?) '${q(n.column)} ${n.op} ${bind(n.vector)}::vector',
      if (_orderBy case final o?) '${q(o)} ${_ascending ? 'ASC' : 'DESC'}',
    ];
    if (order.isNotEmpty) sql += ' ORDER BY ${order.join(', ')}';
    if (_limit != null) sql += ' LIMIT ${bind(_limit)}';
    if (_offset != null) sql += ' OFFSET ${bind(_offset)}';
    return (sql: sql, params: params);
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
    if (_filters.any((f) => f.op != 'eq') || _textSearches.isNotEmpty || _nearest != null) {
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
