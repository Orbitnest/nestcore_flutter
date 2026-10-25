import 'dart:developer' as developer;

import 'env_config.dart';

/// Logger service for NestCore package
class NestCoreLogger {
  static const String _name = 'NestCore';

  /// Log debug message
  static void debug(String message, [Object? error, StackTrace? stackTrace]) {
    if (EnvConfig.isInitialized && EnvConfig.isDebugMode) {
      developer.log(
        message,
        name: _name,
        level: 500, // Debug level
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Log info message
  static void info(String message, [Object? error, StackTrace? stackTrace]) {
    if (EnvConfig.isInitialized && EnvConfig.isDebugMode) {
      developer.log(
        message,
        name: _name,
        level: 800, // Info level
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Log warning message
  static void warning(String message, [Object? error, StackTrace? stackTrace]) {
    if (EnvConfig.isInitialized && EnvConfig.isDebugMode) {
      developer.log(
        message,
        name: _name,
        level: 900, // Warning level
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Log error message (always logs in production for monitoring)
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    // Always log errors, even in production, but sanitize sensitive data
    final sanitizedMessage = _sanitizeMessage(message);
    final sanitizedError = _sanitizeError(error);
    
    developer.log(
      sanitizedMessage,
      name: _name,
      level: 1000, // Error level
      error: sanitizedError,
      stackTrace: stackTrace,
    );
  }

  /// Log HTTP request
  static void logRequest(String method, String url, [Map<String, dynamic>? data]) {
    if (EnvConfig.isInitialized && EnvConfig.isDebugMode) {
      developer.log(
        'HTTP Request: $method $url${data != null ? '\nData: $data' : ''}',
        name: '$_name.HTTP',
        level: 500,
      );
    }
  }

  /// Log HTTP response
  static void logResponse(int statusCode, String url, [dynamic data]) {
    if (EnvConfig.isInitialized && EnvConfig.isDebugMode) {
      developer.log(
        'HTTP Response: $statusCode $url${data != null ? '\nData: $data' : ''}',
        name: '$_name.HTTP',
        level: 500,
      );
    }
  }

  /// Log HTTP error
  static void logHttpError(String message, String url, [Object? error]) {
    if (EnvConfig.isInitialized && EnvConfig.isDebugMode) {
      final sanitizedMessage = _sanitizeMessage(message);
      final sanitizedUrl = _sanitizeUrl(url);
      final sanitizedError = _sanitizeError(error);
      
      developer.log(
        'HTTP Error: $sanitizedMessage - $sanitizedUrl',
        name: '$_name.HTTP',
        level: 1000,
        error: sanitizedError,
      );
    }
  }

  /// Sanitize log messages to remove sensitive data
  static String _sanitizeMessage(String message) {
    String sanitized = message;
    
    // Remove JWT tokens (typical format: eyJ...)
    sanitized = sanitized.replaceAll(RegExp(r'eyJ[A-Za-z0-9-_=]+\.[A-Za-z0-9-_=]+\.?[A-Za-z0-9-_.+/=]*'), '***JWT_TOKEN***');
    
    // Remove API keys (long alphanumeric strings)
    sanitized = sanitized.replaceAll(RegExp(r'[a-zA-Z0-9]{32,}'), '***API_KEY***');
    
    // Remove passwords and sensitive fields
    final sensitivePatterns = [
      RegExp(r'password["\s]*[:=]["\s]*[^,}\s]+', caseSensitive: false),
      RegExp(r'token["\s]*[:=]["\s]*[^,}\s]+', caseSensitive: false),
      RegExp(r'secret["\s]*[:=]["\s]*[^,}\s]+', caseSensitive: false),
      RegExp(r'key["\s]*[:=]["\s]*[^,}\s]+', caseSensitive: false),
    ];
    
    for (final pattern in sensitivePatterns) {
      sanitized = sanitized.replaceAllMapped(pattern, (match) {
        final field = match.group(0)?.split(RegExp(r'[:=]'))[0] ?? 'field';
        return '$field: ***REDACTED***';
      });
    }
    
    return sanitized;
  }

  /// Sanitize URLs to remove sensitive query parameters
  static String _sanitizeUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final sanitizedParams = <String, String>{};
      
      uri.queryParameters.forEach((key, value) {
        final lowerKey = key.toLowerCase();
        if (lowerKey.contains('token') || 
            lowerKey.contains('key') || 
            lowerKey.contains('password') ||
            lowerKey.contains('secret')) {
          sanitizedParams[key] = '***REDACTED***';
        } else {
          sanitizedParams[key] = value;
        }
      });
      
      return uri.replace(queryParameters: sanitizedParams).toString();
    } catch (e) {
      // If URL parsing fails, just return the original (it's likely already safe)
      return url;
    }
  }

  /// Sanitize error objects
  static Object? _sanitizeError(Object? error) {
    if (error == null) return null;
    
    final errorString = error.toString();
    return _sanitizeMessage(errorString);
  }
}