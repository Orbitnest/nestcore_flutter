import '../services/database_service.dart';
import '../models/postgrest_response.dart';
import '../models/table_schema.dart';
import '../exceptions/database_exception.dart';

/// Repository for database operations
/// Provides a layer of abstraction between the BLoC and the service
class DatabaseRepository {
  final DatabaseService _databaseService;

  DatabaseRepository({
    required DatabaseService databaseService,
  }) : _databaseService = databaseService;

  /// Execute raw SQL query
  Future<PostgrestResponse<Map<String, dynamic>>> executeSql({
    required String sql,
    List<dynamic>? parameters,
  }) async {
    try {
      return await _databaseService.executeSql(
        sql: sql,
        parameters: parameters,
      );
    } catch (e) {
      throw DatabaseException.fromException(e);
    }
  }

  /// Get list of tables
  Future<List<TableInfo>> listTables() async {
    try {
      return await _databaseService.listTables();
    } catch (e) {
      throw DatabaseException.fromException(e);
    }
  }

  /// Get table schema
  Future<TableSchema> getTableSchema(String tableName) async {
    try {
      return await _databaseService.getTableSchema(tableName);
    } catch (e) {
      throw DatabaseException.fromException(e);
    }
  }

  /// Enable RLS for a table
  Future<void> enableRls(String tableName) async {
    try {
      await _databaseService.enableRls(tableName);
    } catch (e) {
      throw DatabaseException.fromException(e);
    }
  }

  /// Disable RLS for a table
  Future<void> disableRls(String tableName) async {
    try {
      await _databaseService.disableRls(tableName);
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
      await _databaseService.createPolicy(
        tableName: tableName,
        policyName: policyName,
        command: command,
        role: role,
        using: using,
        withCheck: withCheck,
      );
    } catch (e) {
      throw DatabaseException.fromException(e);
    }
  }

  /// List RLS policies for a table
  Future<List<RlsPolicy>> listPolicies(String tableName) async {
    try {
      return await _databaseService.listPolicies(tableName);
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
      await _databaseService.deletePolicy(
        tableName: tableName,
        policyName: policyName,
      );
    } catch (e) {
      throw DatabaseException.fromException(e);
    }
  }

  /// Execute a query (used by PostgrestQueryBuilder)
  Future<PostgrestResponse<Map<String, dynamic>>> executeQuery({
    required String table,
    String select = '*',
    List<String>? filters,
    String? orderBy,
    bool ascending = true,
    int? limit,
    int? offset,
  }) =>
      _databaseService.executeQuery(
        table: table,
        select: select,
        filters: filters,
        orderBy: orderBy,
        ascending: ascending,
        limit: limit,
        offset: offset,
      );

  /// Insert data
  Future<PostgrestResponse<Map<String, dynamic>>> insert({
    required String table,
    required Map<String, dynamic> values,
    bool upsert = false,
  }) =>
      _databaseService.insert(table: table, values: values, upsert: upsert);

  /// Update rows matching [match] (column = value, AND-ed)
  Future<PostgrestResponse<Map<String, dynamic>>> update({
    required String table,
    required Map<String, dynamic> values,
    required Map<String, dynamic> match,
  }) =>
      _databaseService.updateWhere(table: table, values: values, match: match);

  /// Delete rows matching [match] (column = value, AND-ed)
  Future<PostgrestResponse<Map<String, dynamic>>> delete({
    required String table,
    required Map<String, dynamic> match,
  }) =>
      _databaseService.deleteWhere(table: table, match: match);

  /// Bulk insert (one request per row)
  Future<PostgrestResponse<Map<String, dynamic>>> bulkInsert({
    required String table,
    required List<Map<String, dynamic>> values,
  }) =>
      _databaseService.bulkInsert(table: table, values: values);

  /// Bulk update by explicit match column
  Future<int> bulkUpdate({
    required String table,
    required List<Map<String, dynamic>> values,
    required String matchColumn,
  }) =>
      _databaseService.bulkUpdate(
          table: table, values: values, matchColumn: matchColumn);

  /// Bulk delete by explicit ids
  Future<int> bulkDelete({
    required String table,
    required List<dynamic> ids,
    String idColumn = 'id',
  }) =>
      _databaseService.bulkDelete(table: table, ids: ids, idColumn: idColumn);
}
