import 'package:dio/dio.dart';
import '../../client/interceptors/error_interceptor.dart';

/// Database-specific exception
class DatabaseException extends NestCoreException {
  const DatabaseException(
    super.message, {
    super.code,
    super.statusCode,
    super.body,
    this.table,
    this.query,
    this.hint,
    this.details,
  });

  final String? table;
  final String? query;
  final String? hint;
  final String? details;

  factory DatabaseException.fromException(dynamic error) {
    if (error is DatabaseException) {
      return error;
    }

    if (error is NestCoreException) {
      return DatabaseException(
        error.message,
        code: error.code,
        statusCode: error.statusCode,
        body: error.body,
      );
    }

    // Dio wraps NestCoreException inside DioException.error after ErrorInterceptor.
    // Unwrap it so the caller sees the real code (e.g. UNAUTHORIZED) instead of
    // UNKNOWN_DATABASE_ERROR.
    if (error is DioException) {
      final inner = error.error;
      if (inner is NestCoreException) {
        return DatabaseException(
          inner.message,
          code: inner.code,
          statusCode: inner.statusCode ?? error.response?.statusCode,
          body: inner.body,
        );
      }
      final msg = error.message ?? error.toString();
      final status = error.response?.statusCode;
      return DatabaseException(
        msg,
        code: status == 401 ? 'UNAUTHORIZED' : 'UNKNOWN_DATABASE_ERROR',
        statusCode: status,
      );
    }

    return DatabaseException(
      error.toString(),
      code: 'UNKNOWN_DATABASE_ERROR',
    );
  }

  factory DatabaseException.tableNotFound(String table, [String? message]) {
    return DatabaseException(
      message ?? 'Table "$table" not found',
      code: 'TABLE_NOT_FOUND',
      statusCode: 404,
      table: table,
    );
  }

  factory DatabaseException.columnNotFound(String column, String table, [String? message]) {
    return DatabaseException(
      message ?? 'Column "$column" not found in table "$table"',
      code: 'COLUMN_NOT_FOUND',
      statusCode: 404,
      table: table,
    );
  }

  factory DatabaseException.invalidQuery(String query, [String? message]) {
    return DatabaseException(
      message ?? 'Invalid query',
      code: 'INVALID_QUERY',
      statusCode: 400,
      query: query,
    );
  }

  factory DatabaseException.permissionDenied([String? message]) {
    return DatabaseException(
      message ?? 'Permission denied',
      code: 'PERMISSION_DENIED',
      statusCode: 403,
    );
  }

  factory DatabaseException.constraintViolation([String? message]) {
    return DatabaseException(
      message ?? 'Constraint violation',
      code: 'CONSTRAINT_VIOLATION',
      statusCode: 400,
    );
  }

  factory DatabaseException.rlsViolation([String? message]) {
    return DatabaseException(
      message ?? 'Row Level Security policy violation',
      code: 'RLS_VIOLATION',
      statusCode: 403,
    );
  }

  factory DatabaseException.syntaxError(String query, [String? message]) {
    return DatabaseException(
      message ?? 'SQL syntax error',
      code: 'SYNTAX_ERROR',
      statusCode: 400,
      query: query,
    );
  }

  factory DatabaseException.connectionError([String? message]) {
    return DatabaseException(
      message ?? 'Database connection error',
      code: 'CONNECTION_ERROR',
      statusCode: 500,
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    
    if (code != null) {
      buffer.write('DatabaseException($code): ');
    } else {
      buffer.write('DatabaseException: ');
    }
    
    buffer.write(message);
    
    if (table != null) {
      buffer.write(' [table: $table]');
    }
    
    if (query != null) {
      buffer.write(' [query: $query]');
    }
    
    if (hint != null) {
      buffer.write(' [hint: $hint]');
    }
    
    return buffer.toString();
  }
}