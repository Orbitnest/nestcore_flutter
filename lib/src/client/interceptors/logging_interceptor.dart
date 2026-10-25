import 'package:dio/dio.dart';
import '../../utils/logger.dart';

/// Interceptor for logging HTTP requests and responses
class LoggingInterceptor extends Interceptor {
  final bool logRequests;
  final bool logResponses;
  final bool logErrors;

  LoggingInterceptor({
    this.logRequests = true,
    this.logResponses = true,
    this.logErrors = true,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (logRequests) {
      _logRequest(options);
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (logResponses) {
      _logResponse(response);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (logErrors) {
      _logError(err);
    }
    handler.next(err);
  }

  void _logRequest(RequestOptions options) {
    NestCoreLogger.logRequest(
      options.method.toUpperCase(),
      options.uri.toString(),
      {
        'headers': _sanitizeHeaders(options.headers),
        if (options.data != null) 'data': _sanitizeData(options.data),
        if (options.queryParameters.isNotEmpty) 'queryParameters': options.queryParameters,
      },
    );
  }

  void _logResponse(Response response) {
    NestCoreLogger.logResponse(
      response.statusCode ?? 0,
      response.requestOptions.uri.toString(),
      {
        'headers': _sanitizeHeaders(response.headers.map),
        // Redact secrets (e.g. access_token / refresh_token returned by
        // /auth/* endpoints) BEFORE truncating, so tokens never hit the log.
        if (response.data != null)
          'data': _truncateData(_sanitizeData(response.data)),
      },
    );
  }

  void _logError(DioException error) {
    NestCoreLogger.logHttpError(
      '${error.type}: ${error.message}',
      error.requestOptions.uri.toString(),
      error.response != null
          ? 'Status: ${error.response?.statusCode}, Data: ${error.response?.data}'
          : null,
    );
  }

  Map<String, dynamic> _sanitizeHeaders(Map<String, dynamic> headers) {
    final sanitized = Map<String, dynamic>.from(headers);
    
    // Comprehensive list of sensitive headers
    final sensitiveKeys = [
      'authorization', 
      'apikey', 
      'x-api-key', 
      'cookie',
      'x-auth-token',
      'x-access-token',
      'bearer',
      'x-jwt-token',
      'x-session-token',
      'x-refresh-token',
      'x-csrf-token',
      'x-client-secret',
      'x-api-secret',
    ];
    
    for (final key in sensitiveKeys) {
      final lowerKey = key.toLowerCase();
      for (final headerKey in sanitized.keys.toList()) {
        if (headerKey.toString().toLowerCase().contains(lowerKey)) {
          sanitized[headerKey] = '***REDACTED***';
        }
      }
    }
    
    return sanitized;
  }

  dynamic _sanitizeData(dynamic data) {
    if (data is Map) {
      final sanitized = Map<String, dynamic>.from(data);
      
      // Comprehensive list of sensitive data fields
      final sensitiveFields = [
        'password',
        'pwd', 
        'passwd',
        'token', 
        'access_token', 
        'refresh_token',
        'id_token',
        'jwt_token',
        'auth_token',
        'session_token',
        'api_key',
        'apikey', 
        'secret',
        'client_secret',
        'private_key',
        'encryption_key',
        'auth_code',
        'otp',
        'pin',
        'ssn',
        'social_security_number',
        'credit_card',
        'card_number',
        'cvv',
        'cvc',
        'bank_account',
        'routing_number',
        'personal_access_token',
        'bearer_token',
      ];
      
      // Check all keys for sensitive patterns
      for (final key in sanitized.keys.toList()) {
        final lowerKey = key.toString().toLowerCase();
        
        // Direct match or contains sensitive pattern
        if (sensitiveFields.any((field) => 
            lowerKey == field || 
            lowerKey.contains(field) ||
            (field.contains('password') && lowerKey.contains('pass')) ||
            (field.contains('token') && lowerKey.contains('token')) ||
            (field.contains('key') && lowerKey.contains('key'))
        )) {
          sanitized[key] = '***REDACTED***';
        }
      }
      
      // Recursively sanitize nested objects
      for (final key in sanitized.keys.toList()) {
        if (sanitized[key] is Map || sanitized[key] is List) {
          sanitized[key] = _sanitizeData(sanitized[key]);
        }
      }
      
      return sanitized;
    } else if (data is List) {
      return data.map((item) => _sanitizeData(item)).toList();
    }
    
    return data;
  }

  dynamic _truncateData(dynamic data) {
    final dataString = data.toString();
    if (dataString.length > 1000) {
      return '${dataString.substring(0, 1000)}... [TRUNCATED]';
    }
    return data;
  }
}