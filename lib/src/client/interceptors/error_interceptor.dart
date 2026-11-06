import 'package:dio/dio.dart';
import '../../constants/error_codes.dart';

/// Interceptor for handling HTTP errors and transforming them into meaningful exceptions
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    NestCoreException exception;

    switch (err.type) {
      case DioExceptionType.connectionTimeout:
        exception = const NestCoreException(
          'Connection timeout',
          code: ErrorCodes.connectionTimeout,
        );
        break;
      case DioExceptionType.sendTimeout:
        exception = const NestCoreException(
          'Send timeout',
          code: ErrorCodes.sendTimeout,
        );
        break;
      case DioExceptionType.receiveTimeout:
        exception = const NestCoreException(
          'Receive timeout',
          code: ErrorCodes.receiveTimeout,
        );
        break;
      case DioExceptionType.badCertificate:
        exception = const NestCoreException(
          'Bad certificate',
          code: ErrorCodes.badCertificate,
        );
        break;
      case DioExceptionType.connectionError:
        exception = NestCoreException(
          'Connection error: ${err.message}',
          code: ErrorCodes.connectionError,
        );
        break;
      case DioExceptionType.badResponse:
        exception = _handleBadResponse(err);
        break;
      case DioExceptionType.cancel:
        exception = const NestCoreException(
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
        
        exception = NestCoreException(
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

  NestCoreException _handleBadResponse(DioException err) {
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
    return NestCoreException(
      message.isEmpty ? fallback : message,
      code: code ?? defaultCode,
      statusCode: statusCode,
      body: data is Map<String, dynamic> ? data : null,
    );
  }
}

/// Base exception class for NestCore errors
class NestCoreException implements Exception {
  const NestCoreException(
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

  /// 423: the project is paused (plan limit or owner) or compromised (kill
  /// switch). Nothing was deleted; calls work again once it is resumed.
  bool get isProjectPaused => code == ErrorCodes.projectPaused;

  /// 402 `QUOTA_EXCEEDED`: where to send the user to upgrade, when given.
  String? get upgradeUrl {
    final u = body?['upgradeUrl'];
    return u is String ? u : null;
  }

  /// 402 `CREDITS_EXHAUSTED`: the workspace's prepaid AI credit cannot pay
  /// for this call (see [creditsReason]). Offer [buyUrl] or adding your own
  /// provider key; don't retry.
  bool get isCreditsExhausted => code == ErrorCodes.creditsExhausted;

  /// `balance` (no credit left) or `spend_cap` (the monthly cap is reached),
  /// for `CREDITS_EXHAUSTED`.
  String? get creditsReason {
    final r = body?['reason'];
    return isCreditsExhausted && r is String ? r : null;
  }

  /// 402 `CREDITS_EXHAUSTED`: where to buy more credit, when given.
  String? get buyUrl {
    final u = body?['buyUrl'];
    return u is String ? u : null;
  }

  @override
  String toString() {
    if (code != null) {
      return 'NestCoreException($code): $message';
    }
    return 'NestCoreException: $message';
  }
}