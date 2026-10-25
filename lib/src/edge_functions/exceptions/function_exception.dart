import 'package:dio/dio.dart';
import '../../client/interceptors/error_interceptor.dart';

/// Edge function-specific exception
class FunctionException extends NestCoreException {
  const FunctionException(
    super.message, {
    super.code,
    super.statusCode,
    super.body,
    this.functionName,
    this.executionId,
    this.executionTimeMs,
  });

  final String? functionName;
  final String? executionId;
  final int? executionTimeMs;

  factory FunctionException.fromException(dynamic error) {
    if (error is FunctionException) {
      return error;
    }

    if (error is NestCoreException) {
      return FunctionException(
        error.message,
        code: error.code,
        statusCode: error.statusCode,
        body: error.body,
      );
    }

    // ErrorInterceptor wraps the API error (code, message, body) in DioException.error.
    if (error is DioException && error.error is NestCoreException) {
      return FunctionException.fromException(error.error);
    }

    return FunctionException(
      error.toString(),
      code: 'UNKNOWN_FUNCTION_ERROR',
    );
  }

  factory FunctionException.functionNotFound(String functionName, [String? message]) {
    return FunctionException(
      message ?? 'Function "$functionName" not found',
      code: 'FUNCTION_NOT_FOUND',
      statusCode: 404,
      functionName: functionName,
    );
  }

  factory FunctionException.executionError(
    String functionName, 
    String error, [
    String? executionId,
    int? executionTimeMs,
  ]) {
    return FunctionException(
      'Function execution failed: $error',
      code: 'FUNCTION_EXECUTION_ERROR',
      statusCode: 500,
      functionName: functionName,
      executionId: executionId,
      executionTimeMs: executionTimeMs,
    );
  }

  factory FunctionException.timeout(
    String functionName, 
    int timeoutMs, [
    String? executionId,
  ]) {
    return FunctionException(
      'Function "$functionName" timed out after ${timeoutMs}ms',
      code: 'FUNCTION_TIMEOUT',
      statusCode: 408,
      functionName: functionName,
      executionId: executionId,
      executionTimeMs: timeoutMs,
    );
  }

  factory FunctionException.invalidRequest([String? message]) {
    return FunctionException(
      message ?? 'Invalid function request',
      code: 'INVALID_FUNCTION_REQUEST',
      statusCode: 400,
    );
  }

  factory FunctionException.unauthorized([String? message]) {
    return FunctionException(
      message ?? 'Unauthorized function access',
      code: 'UNAUTHORIZED_FUNCTION_ACCESS',
      statusCode: 401,
    );
  }

  factory FunctionException.forbidden([String? message]) {
    return FunctionException(
      message ?? 'Function access forbidden',
      code: 'FUNCTION_ACCESS_FORBIDDEN',
      statusCode: 403,
    );
  }

  factory FunctionException.rateLimitExceeded([String? message]) {
    return FunctionException(
      message ?? 'Function rate limit exceeded',
      code: 'FUNCTION_RATE_LIMIT_EXCEEDED',
      statusCode: 429,
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    
    if (code != null) {
      buffer.write('FunctionException($code): ');
    } else {
      buffer.write('FunctionException: ');
    }
    
    buffer.write(message);
    
    if (functionName != null) {
      buffer.write(' [function: $functionName]');
    }
    
    if (executionId != null) {
      buffer.write(' [execution: $executionId]');
    }
    
    if (executionTimeMs != null) {
      buffer.write(' [time: ${executionTimeMs}ms]');
    }
    
    return buffer.toString();
  }
}