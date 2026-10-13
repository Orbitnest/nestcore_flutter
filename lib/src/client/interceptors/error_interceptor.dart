import 'package:dio/dio.dart';
import '../../constants/error_codes.dart';

/// Interceptor for handling HTTP errors and transforming them into meaningful exceptions
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    OrbitNestException exception;

    switch (err.type) {
      case DioExceptionType.connectionTimeout:
        exception = const OrbitNestException(
          'Connection timeout',
          code: ErrorCodes.connectionTimeout,
        );
        break;
      case DioExceptionType.sendTimeout:
        exception = const OrbitNestException(
          'Send timeout',
          code: ErrorCodes.sendTimeout,
        );
        break;
      case DioExceptionType.receiveTimeout:
        exception = const OrbitNestException(
          'Receive timeout',
          code: ErrorCodes.receiveTimeout,
        );
        break;
      case DioExceptionType.badCertificate:
        exception = const OrbitNestException(
          'Bad certificate',
          code: ErrorCodes.badCertificate,
        );
        break;
      case DioExceptionType.connectionError:
        exception = OrbitNestException(
          'Connection error: ${err.message}',
          code: ErrorCodes.connectionError,
        );
        break;
      case DioExceptionType.badResponse:
        exception = _handleBadResponse(err);
        break;
      case DioExceptionType.cancel:
        exception = const OrbitNestException(
          'Request cancelled',
          code: ErrorCodes.requestCancelled,
        );
        break;
      case DioExceptionType.unknown:
        // Handle timeout and other unknown errors more gracefully
        String message = 'Unknown error';
        String code = ErrorCodes.unknownError;
        
        if (err.message?.toLowerCase().contains('timeout') == true ||
            err.error?.toString().toLowerCase().contains('timeout') == true) {
          message = 'Operation timeout';
          code = ErrorCodes.operationTimeout;
        } else if (err.message != null && err.message!.isNotEmpty) {
          message = 'Unknown error: ${err.message}';
        } else if (err.error != null) {
          message = 'Unknown error: ${err.error}';
        }
        
        exception = OrbitNestException(
          message,
          code: code,
        );
        break;
    }

    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        error: exception,
        type: err.type,
        response: err.response,
        message: exception.message,
      ),
    );
  }

  OrbitNestException _handleBadResponse(DioException err) {
    final response = err.response;
    final statusCode = response?.statusCode;
    final data = response?.data;

    String message = 'HTTP Error';
    String? code;

    if (data is Map<String, dynamic>) {
      // NestJS validation errors send `message` as a list of strings.
      final m = data['message'] ?? data['error'];
      if (m is List) {
        message = m.join(', ');
      } else if (m != null) {
        message = m.toString();
      }
      code = data['code']?.toString();
    } else if (data is String) {
      message = data;
    }

    final (fallback, defaultCode) = switch (statusCode) {
      400 => ('Bad Request', ErrorCodes.badRequest),
      401 => ('Unauthorized', ErrorCodes.unauthorized),
      403 => ('Forbidden', ErrorCodes.forbidden),
      404 => ('Not Found', ErrorCodes.notFound),
      429 => ('Too Many Requests', ErrorCodes.rateLimitExceeded),
      500 => ('Internal Server Error', ErrorCodes.internalServerError),
      502 => ('Bad Gateway', ErrorCodes.badGateway),
      503 => ('Service Unavailable', ErrorCodes.serviceUnavailable),
      _ => ('HTTP Error $statusCode', ErrorCodes.httpError),
    };
    return OrbitNestException(
      message.isEmpty ? fallback : message,
      code: code ?? defaultCode,
      statusCode: statusCode,
      body: data is Map<String, dynamic> ? data : null,
    );
  }
}

/// Base exception class for OrbitNest errors
class OrbitNestException implements Exception {
  const OrbitNestException(
    this.message, {
    this.code,
    this.statusCode,
    this.body,
  });

  final String message;
  final String? code;
  final int? statusCode;

  /// Parsed JSON error body, with any structured fields the API sent
  /// (e.g. `QUOTA_EXCEEDED`'s `quota`/`plan`/`limit`/`usage`).
  final Map<String, dynamic>? body;

  @override
  String toString() {
    if (code != null) {
      return 'OrbitNestException($code): $message';
    }
    return 'OrbitNestException: $message';
  }
}