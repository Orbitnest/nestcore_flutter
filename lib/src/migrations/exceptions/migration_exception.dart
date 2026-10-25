import '../../client/interceptors/error_interceptor.dart';

/// Migration-specific exception.
class MigrationException extends NestCoreException {
  const MigrationException(
    super.message, {
    super.code,
    super.statusCode,
  });

  factory MigrationException.fromException(dynamic error) {
    if (error is MigrationException) return error;

    if (error is NestCoreException) {
      return MigrationException(
        error.message,
        code: error.code,
        statusCode: error.statusCode,
      );
    }

    return MigrationException(
      error.toString(),
      code: 'UNKNOWN_MIGRATION_ERROR',
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer('MigrationException');
    if (code != null) buffer.write('($code)');
    buffer.write(': $message');
    return buffer.toString();
  }
}
