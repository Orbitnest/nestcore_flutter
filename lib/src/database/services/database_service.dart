import 'package:dio/dio.dart' show Response;
import '../../client/http_client.dart';
import '../../constants/endpoints.dart';
import '../models/postgrest_response.dart';
import '../models/table_schema.dart';
import '../exceptions/database_exception.dart';

/// Service for handling database API calls
class DatabaseService {
  final OrbitNestHttpClient _httpClient;
  final String _projectSlug;

  DatabaseService({
    required OrbitNestHttpClient httpClient,
    required String projectSlug,
  }) : _httpClient = httpClient,
       _projectSlug = projectSlug;

  /// Execute raw SQL. Positional placeholders are `$1`, `$2`, … and are bound
  /// from [parameters]. Returns the result rows; `count` is `rows_affected`.
  Future<PostgrestResponse<Map<String, dynamic>>> executeSql({
    required String sql,
    List<dynamic>? parameters,
  }) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectDatabaseSql(_projectSlug),
        // The API DTO field is `params`; unknown fields are rejected with 400.
        data: {
          'sql': sql,
          if (parameters != null) 'params': parameters,
        },
      );
      // Response: {success, execution_time_ms, rows_affected, columns, data: [...rows], message}
      final body = response.data;
      return PostgrestResponse<Map<String, dynamic>>(
        data: _rows(body),
        count: body is Map ? (body['rows_affected'] as num?)?.toInt() : null,
        status: response.statusCode,
      );
    } catch (e) {
      throw DatabaseException.fromException(e);
    }
  }

  /// Get list of tables
  Future<List<TableInfo>> listTables() async {
    try {
      final response = await _httpClient.get(
        Endpoints.projectDatabaseTablesList(_projectSlug),
      );

      final data = response.data as List;
      return data.map((item) => TableInfo.fromJson(item)).toList();
    } catch (e) {
      throw DatabaseException.fromException(e);
    }
  }

  /// Get table schema
  Future<TableSchema> getTableSchema(String tableName) async {
    try {
      final response = await _httpClient.get(
        Endpoints.projectDatabaseTables(_projectSlug),
        queryParameters: {'table': tableName},
      );
      final List<dynamic> items =
          response.data is List ? response.data as List : [response.data];
      if (items.isEmpty) {
        throw DatabaseException('Table not found: $tableName');
      }
      return TableSchema.fromJson(items.first as Map<String, dynamic>);
    } catch (e) {
      throw DatabaseException.fromException(e);
    }
  }

  /// Enable RLS for a table
  Future<void> enableRls(String tableName) async {
    try {
      await _httpClient.post(
        Endpoints.projectDatabaseTableEnableRls(_projectSlug, tableName),
      );
    } catch (e) {
      throw DatabaseException.fromException(e);
    }
  }

  /// Disable RLS for a table
  Future<void> disableRls(String tableName) async {
    try {
      await _httpClient.post(
        Endpoints.projectDatabaseTableDisableRls(_projectSlug, tableName),
      );
    } catch (e) {
      throw DatabaseException.fromException(e);
    }
  }

  /// Create RLS policy
  Future<void> createPolicy({
    required String tableName,
    required String policyName,
    required String command,
    String? role,
    String? using,
    String? withCheck,
  }) async {
    try {
      await _httpClient.post(
        Endpoints.projectDatabaseTablePolicies(_projectSlug, tableName),
        data: {
          'name': policyName,
          'command': command,
          if (role != null) 'role': role,
          if (using != null) 'using': using,
          if (withCheck != null) 'with_check': withCheck,
        },
      );
    } catch (e) {
      throw DatabaseException.fromException(e);
    }
  }

  /// List RLS policies for a table
  Future<List<RlsPolicy>> listPolicies(String tableName) async {
    try {
      final response = await _httpClient.get(
        Endpoints.projectDatabaseTablePolicies(_projectSlug, tableName),
      );

      final data = response.data as List;
      return data.map((item) => RlsPolicy.fromJson(item)).toList();
    } catch (e) {
      throw DatabaseException.fromException(e);
    }
  }

  /// Delete RLS policy
  Future<void> deletePolicy({
    required String tableName,
    required String policyName,
  }) async {
    try {
      await _httpClient.delete(
        Endpoints.projectDatabaseTablePolicyByName(_projectSlug, tableName, policyName),
      );
    } catch (e) {
      throw DatabaseException.fromException(e);
    }
  }


  /// Filter operators the API's `filter=column:operator:value` parser supports
  /// (`database-ops.service.ts` getTableData). Anything else is silently
  /// ignored server-side, which would return unfiltered rows — so we reject it.
  static const supportedFilterOperators = {
    'eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'like', 'ilike', 'in', 'is',
  };

  /// Encode one filter as `column:operator:value` for the data endpoint.
  /// Throws instead of sending a filter the server would drop.
  static String encodeFilter(String column, String operator, Object? value) {
    var op = operator.toLowerCase();
    if (op == 'eq' && value == null) op = 'is';
    if (!supportedFilterOperators.contains(op)) {
      throw UnsupportedError(
          'Filter operator "$operator" is not supported by the OrbitNest data API. '
          'Supported: ${supportedFilterOperators.join(', ')}. Use database.sql() for other queries.');
    }
    if (!_identifier.hasMatch(column)) {
      throw ArgumentError.value(column, 'column', 'Invalid column name');
    }
    final String v;
    if (op == 'in') {
      if (value is! Iterable || value.isEmpty) {
        throw ArgumentError.value(value, 'value', '"in" needs a non-empty list');
      }
      final items = value.map((e) => '$e').toList();
      if (items.any((e) => e.contains(','))) {
        throw ArgumentError.value(value, 'value', '"in" values cannot contain ","');
      }
      v = items.join(',');
    } else {
      v = '$value';
    }
    if (op == 'is' && !const {'null', 'true', 'false'}.contains(v.toLowerCase())) {
      throw ArgumentError.value(value, 'value', '"is" accepts only null, true or false');
    }
    return '$column:$op:$v';
  }

  /// Read rows: `GET /database/tables/:table/data` with repeatable `filter`,
  /// `sortBy`/`sortOrder` and `limit` (or `from`/`to` when [offset] is set).
  /// The server caps a page at 100 rows. [select] is applied client-side
  /// (plain column lists only — the API always returns every column).
  Future<PostgrestResponse<Map<String, dynamic>>> executeQuery({
    required String table,
    String select = '*',
    List<String>? filters,
    String? orderBy,
    bool ascending = true,
    int? limit,
    int? offset,
  }) async {
    final columns = _parseSelect(select);
    final queryParams = <String, dynamic>{
      if (filters != null && filters.isNotEmpty) 'filter': filters,
      if (orderBy != null) 'sortBy': orderBy,
      if (orderBy != null) 'sortOrder': ascending ? 'ASC' : 'DESC',
    };
    if (offset != null) {
      queryParams['from'] = '$offset';
      queryParams['to'] = '${offset + (limit ?? 50) - 1}';
    } else if (limit != null) {
      queryParams['limit'] = '$limit';
    }

    try {
      final response = await _httpClient.get(
        Endpoints.projectDatabaseTableData(_projectSlug, table),
        queryParameters: queryParams,
      );
      // {success, table_name, total_rows, returned_rows, page, limit, columns, data: [...]}
      final body = response.data;
      var rows = _rows(body);
      if (columns != null) {
        rows = rows
            .map((r) => {for (final c in columns) if (r.containsKey(c)) c: r[c]})
            .toList();
      }
      return PostgrestResponse<Map<String, dynamic>>(
        data: rows,
        count: body is Map ? (body['total_rows'] as num?)?.toInt() : null,
        status: response.statusCode,
      );
    } catch (e) {
      throw DatabaseException.fromException(e);
    }
  }

  /// Insert one row; returns the inserted row (server-generated fields included).
  /// The API has no upsert, so [upsert] throws rather than silently inserting.
  Future<PostgrestResponse<Map<String, dynamic>>> insert({
    required String table,
    required Map<String, dynamic> values,
    bool upsert = false,
  }) async {
    if (upsert) throw upsertUnsupported();
    try {
      final response = await _httpClient.post(
        Endpoints.projectDatabaseTableRows(_projectSlug, table),
        data: values,
      );
      final body = response.data;
      return PostgrestResponse<Map<String, dynamic>>(
        data: _rows(body),
        count: body is Map ? (body['rows_affected'] as num?)?.toInt() : null,
        status: response.statusCode,
      );
    } catch (e) {
      throw DatabaseException.fromException(e);
    }
  }

  /// Insert several rows, one request each. The bulk-insert route requires
  /// the service-role key, which a client app never holds.
  /// shortcut: not atomic — rows inserted before a failure stay; upgrade when
  /// the API allows user-token bulk insert.
  Future<PostgrestResponse<Map<String, dynamic>>> bulkInsert({
    required String table,
    required List<Map<String, dynamic>> values,
  }) async {
    final rows = <Map<String, dynamic>>[];
    for (final v in values) {
      rows.addAll((await insert(table: table, values: v)).data);
    }
    return PostgrestResponse<Map<String, dynamic>>(data: rows, count: rows.length);
  }

  /// Update every row whose columns equal [match] (AND). Returns no rows;
  /// `count` is the number of rows updated. Needs a signed-in user (RLS applies).
  Future<PostgrestResponse<Map<String, dynamic>>> updateWhere({
    required String table,
    required Map<String, dynamic> values,
    required Map<String, dynamic> match,
  }) async {
    if (values.isEmpty) throw ArgumentError('update values cannot be empty');
    _requireMatch(match);
    return _bulk(
      () => _httpClient.put(
        Endpoints.projectDatabaseTableBulkUpdate(_projectSlug, table),
        data: [
          {'where': match, 'data': values}
        ],
      ),
    );
  }

  /// Delete every row whose columns equal [match] (AND). `count` is the number
  /// of rows deleted. Needs a signed-in user (RLS applies).
  Future<PostgrestResponse<Map<String, dynamic>>> deleteWhere({
    required String table,
    required Map<String, dynamic> match,
  }) async {
    _requireMatch(match);
    return _bulk(
      () => _httpClient.delete(
        Endpoints.projectDatabaseTableBulkDelete(_projectSlug, table),
        data: [match],
      ),
    );
  }

  /// Bulk update with an explicit match column: each row's [matchColumn] value
  /// selects the row, the remaining keys are the new values.
  Future<int> bulkUpdate({
    required String table,
    required List<Map<String, dynamic>> values,
    required String matchColumn,
  }) async {
    if (values.isEmpty || values.any((row) => row[matchColumn] == null)) {
      throw ArgumentError('Every row needs a non-null "$matchColumn"');
    }
    final res = await _bulk(
      () => _httpClient.put(
        Endpoints.projectDatabaseTableBulkUpdate(_projectSlug, table),
        data: values.map((row) {
          final data = Map<String, dynamic>.from(row)..remove(matchColumn);
          return {'where': {matchColumn: row[matchColumn]}, 'data': data};
        }).toList(),
      ),
    );
    return res.count ?? 0;
  }

  /// Bulk delete by explicit ids: `DELETE … WHERE idColumn = id` for each id.
  Future<int> bulkDelete({
    required String table,
    required List<dynamic> ids,
    String idColumn = 'id',
  }) async {
    if (ids.isEmpty || ids.any((id) => id == null)) {
      throw ArgumentError('ids must be a non-empty list of non-null values');
    }
    final res = await _bulk(
      () => _httpClient.delete(
        Endpoints.projectDatabaseTableBulkDelete(_projectSlug, table),
        data: ids.map((id) => {idColumn: id}).toList(),
      ),
    );
    return res.count ?? 0;
  }

  Future<PostgrestResponse<Map<String, dynamic>>> _bulk(
    Future<Response<dynamic>> Function() send,
  ) async {
    try {
      final response = await send();
      // {success, rows_affected, message}
      final body = response.data;
      return PostgrestResponse<Map<String, dynamic>>(
        data: const [],
        count: body is Map ? (body['rows_affected'] as num?)?.toInt() : null,
        status: response.statusCode,
      );
    } catch (e) {
      throw DatabaseException.fromException(e);
    }
  }

  static void _requireMatch(Map<String, dynamic> match) {
    // An empty match would target every row (the server rejects it anyway);
    // a null value never matches (`col = NULL`), so the call would silently do nothing.
    if (match.isEmpty) {
      throw ArgumentError('filters cannot be empty — refusing to touch every row');
    }
    if (match.values.any((v) => v == null)) {
      throw ArgumentError('filters cannot contain null values (column = NULL never matches)');
    }
  }

  /// Parse PostgREST-style order strings (`'created_at.desc'`). The API sorts
  /// by one column only, so more than one entry throws rather than being dropped.
  static ({String column, bool ascending})? parseOrder(List<String>? orders) {
    if (orders == null || orders.isEmpty) return null;
    if (orders.length > 1) {
      throw UnsupportedError('The OrbitNest data API sorts by one column only (got $orders)');
    }
    final parts = orders.single.split('.');
    return (column: parts.first.trim(), ascending: !parts.contains('desc'));
  }

  static UnsupportedError upsertUnsupported() => UnsupportedError(
      'Upsert is not supported by the OrbitNest data API. '
      'Insert, catch the duplicate-key DatabaseException, then update.');

  static final _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  /// Columns from a plain `a, b, c` select list; null for `*`.
  static List<String>? _parseSelect(String select) {
    final s = select.trim();
    if (s.isEmpty || s == '*') return null;
    final cols = s.split(',').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
    if (cols.any((c) => !_identifier.hasMatch(c))) {
      throw UnsupportedError(
          'select("$select"): only plain column lists are supported (no *, aliases or embedded relations)');
    }
    return cols;
  }

  static List<Map<String, dynamic>> _rows(dynamic body) {
    final raw = body is Map ? body['data'] : body;
    if (raw is! List) return [];
    return raw.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList();
  }
}
