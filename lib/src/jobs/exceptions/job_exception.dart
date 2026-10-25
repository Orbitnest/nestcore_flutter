import '../../client/interceptors/error_interceptor.dart';

/// Background job-specific exception.
class JobException extends NestCoreException {
  const JobException(
    super.message, {
    super.code,
    super.statusCode,
    this.jobName,
  });

  final String? jobName;

  factory JobException.fromException(dynamic error) {
    if (error is JobException) return error;

    if (error is NestCoreException) {
      return JobException(
        error.message,
        code: error.code,
        statusCode: error.statusCode,
      );
    }

    return JobException(
      error.toString(),
      code: 'UNKNOWN_JOB_ERROR',
    );
  }

  factory JobException.notFound(String name, [String? message]) {
    return JobException(
      message ?? 'Job "$name" not found',
      code: 'JOB_NOT_FOUND',
      statusCode: 404,
      jobName: name,
    );
  }

  factory JobException.alreadyRunning(String name) {
    return JobException(
      'Job "$name" is already running',
      code: 'JOB_ALREADY_RUNNING',
      statusCode: 400,
      jobName: name,
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer('JobException');
    if (code != null) buffer.write('($code)');
    buffer.write(': $message');
    if (jobName != null) buffer.write(' [job: $jobName]');
    return buffer.toString();
  }
}
