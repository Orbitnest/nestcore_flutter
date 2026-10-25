import 'package:dio/dio.dart';
import '../auth/services/token_manager.dart';
import '../constants/constants.dart';
import '../utils/env_config.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/error_interceptor.dart';
import 'interceptors/logging_interceptor.dart';
import 'interceptors/retry_interceptor.dart';
import '../utils/retry_policy.dart';

/// HTTP client for NestCore API calls
class NestCoreHttpClient {
  late final Dio _dio;
  final String baseUrl;
  final TokenManager _tokenManager;

  NestCoreHttpClient({
    required this.baseUrl,
    required TokenManager tokenManager,
  }) : _tokenManager = tokenManager {
    final timeoutMs = EnvConfig.apiTimeout;
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: Duration(milliseconds: timeoutMs),
      receiveTimeout: Duration(milliseconds: timeoutMs),
      sendTimeout: Duration(milliseconds: timeoutMs),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        // Security headers
        'X-Requested-With': 'XMLHttpRequest',
        'X-Client-Info': 'nestcore-flutter/${NestCoreConstants.version}',
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
        'Expires': '0',
      },
      // Additional security options
      validateStatus: (status) {
        // Accept standard HTTP success codes only
        return status != null && status >= 200 && status < 300;
      },
      followRedirects: false, // Prevent automatic redirects for security
      maxRedirects: 0,
    ));

    _setupInterceptors();
  }

  void _setupInterceptors() {
    _dio.interceptors.addAll([
      AuthInterceptor(_tokenManager),
      RetryInterceptor(retryPolicy: RetryPolicy.standard),
      ErrorInterceptor(),
      LoggingInterceptor(),
    ]);
  }

  /// The credentials [AuthInterceptor] adds, for a request made outside Dio
  /// (an abortable stream). That path gets no 401 refresh-and-retry.
  Future<Map<String, String>> authHeaders() => projectAuthHeaders(_tokenManager);

  /// Get request
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    return await _dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
    );
  }

  /// Post request
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    return await _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  /// Put request
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    return await _dio.put<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  /// Delete request
  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return await _dio.delete<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// Patch request
  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    return await _dio.patch<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  /// Generic request method
  Future<Response<T>> request<T>(
    String method,
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    return await _dio.request<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options?.copyWith(method: method) ?? Options(method: method),
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  /// Close the client and clean up resources
  void close({bool force = false}) {
    _dio.close(force: force);
  }
}
