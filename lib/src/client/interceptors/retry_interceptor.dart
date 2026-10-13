import 'package:dio/dio.dart';
import '../../utils/retry_policy.dart';

/// Interceptor that adds automatic retry logic with exponential backoff
class RetryInterceptor extends Interceptor {
  final RetryPolicy retryPolicy;

  RetryInterceptor({
    this.retryPolicy = RetryPolicy.standard,
  });

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Check if we should retry this error
    if (!_shouldRetry(err)) {
      return handler.next(err);
    }

    // Track retry attempts on the request options
    final retryCount = _getRetryCount(err.requestOptions);

    if (retryCount >= retryPolicy.maxRetries) {
      return handler.next(err);
    }

    try {
      // Calculate delay with exponential backoff
      final delay = _calculateDelay(retryCount);

      await Future.delayed(delay);

      // Increment retry count
      _setRetryCount(err.requestOptions, retryCount + 1);

      // Create a new Dio instance to avoid interceptor loops
      final dio = Dio(BaseOptions(
        baseUrl: err.requestOptions.baseUrl,
        connectTimeout: err.requestOptions.connectTimeout,
        receiveTimeout: err.requestOptions.receiveTimeout,
        sendTimeout: err.requestOptions.sendTimeout,
      ));

      // Retry the request
      final response = await dio.request(
        err.requestOptions.path,
        data: err.requestOptions.data,
        queryParameters: err.requestOptions.queryParameters,
        options: Options(
          method: err.requestOptions.method,
          headers: err.requestOptions.headers,
          contentType: err.requestOptions.contentType,
          responseType: err.requestOptions.responseType,
          validateStatus: err.requestOptions.validateStatus,
          followRedirects: err.requestOptions.followRedirects,
          maxRedirects: err.requestOptions.maxRedirects,
        ),
      );

      return handler.resolve(response);
    } catch (e) {
      // If it's a DioException, pass it through for potential further retries
      if (e is DioException) {
        return handler.next(e);
      }

      // Otherwise, pass the original error
      return handler.next(err);
    }
  }

  /// Check if error should be retried
  bool _shouldRetry(DioException error) {
    // Don't retry if explicitly disabled
    if (retryPolicy.maxRetries == 0) {
      return false;
    }

    // A FormData body is finalized by the first send and cannot be re-sent.
    if (error.requestOptions.data is FormData) {
      return false;
    }

    // Retry on timeout errors
    if (retryPolicy.retryOnTimeout &&
        (error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.sendTimeout ||
            error.type == DioExceptionType.receiveTimeout)) {
      return true;
    }

    // Retry on connection errors
    if (retryPolicy.retryOnConnectionError &&
        (error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.unknown)) {
      return true;
    }

    // Retry on specific status codes
    final statusCode = error.response?.statusCode;
    // A coded 429 (SMS_RATE_LIMITED, SHARED_EMAIL_RATE_LIMITED, …) is a
    // minutes-to-hours window; retrying within seconds only delays the error.
    final body = error.response?.data;
    if (statusCode == 429 && body is Map && body['code'] != null) {
      return false;
    }
    if (statusCode != null && retryPolicy.retryableStatusCodes.contains(statusCode)) {
      return true;
    }

    // Don't retry on 4xx errors (except configured ones like 408, 429)
    if (statusCode != null && statusCode >= 400 && statusCode < 500) {
      return false;
    }

    // Don't retry on authentication errors (handled by AuthInterceptor)
    if (statusCode == 401 || statusCode == 403) {
      return false;
    }

    return false;
  }

  /// Get current retry count from request options
  int _getRetryCount(RequestOptions options) {
    return (options.extra['retry_count'] as int?) ?? 0;
  }

  /// Set retry count in request options
  void _setRetryCount(RequestOptions options, int count) {
    options.extra['retry_count'] = count;
  }

  /// Calculate delay with exponential backoff and jitter
  Duration _calculateDelay(int retryCount) {
    final delayMs = retryPolicy.initialDelay.inMilliseconds;
    final maxDelayMs = retryPolicy.maxDelay.inMilliseconds;

    // Calculate exponential backoff: initialDelay * (backoffMultiplier ^ retryCount)
    var exponentialDelay = delayMs;
    for (var i = 0; i < retryCount; i++) {
      exponentialDelay = (exponentialDelay * retryPolicy.backoffMultiplier).toInt();
    }

    // Add jitter (random value between 0 and 10% of delay)
    final jitterRange = (exponentialDelay * 0.1).toInt();
    final jitter = jitterRange > 0 ? (DateTime.now().millisecondsSinceEpoch % jitterRange) : 0;

    // Cap at maxDelay
    final totalDelay = (exponentialDelay + jitter).clamp(delayMs, maxDelayMs);

    return Duration(milliseconds: totalDelay);
  }
}
