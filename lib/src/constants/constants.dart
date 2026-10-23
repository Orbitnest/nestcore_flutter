/// General constants for OrbitNest Studio package
class OrbitNestConstants {
  // Package info
  static const String packageName = 'orbitnest_studio_flutter';
  static const String version = '1.8.0'; // keep in sync with pubspec.yaml

  // Storage keys
  static const String accessTokenKey = 'orbitnest_access_token';
  static const String refreshTokenKey = 'orbitnest_refresh_token';
  static const String sessionKey = 'orbitnest_session';
  static const String apiKeyKey = 'orbitnest_api_key';
  static const String projectSlugKey = 'orbitnest_project_slug';

  // Default timeouts (in seconds)
  static const int defaultConnectTimeout = 60;
  static const int defaultReceiveTimeout = 60;
  static const int defaultSendTimeout = 60;

  // Token refresh settings
  static const int tokenRefreshThreshold = 300; // 5 minutes in seconds
  static const int maxRetryAttempts = 3;

  // HTTP headers
  static const String authorizationHeader = 'Authorization';
  static const String apiKeyHeader = 'apikey';
  static const String contentTypeHeader = 'Content-Type';
  static const String acceptHeader = 'Accept';
  static const String userAgentHeader = 'User-Agent';

  // Content types
  static const String jsonContentType = 'application/json';
  static const String formUrlEncodedContentType = 'application/x-www-form-urlencoded';

  // Auth methods
  static const String bearerTokenType = 'Bearer';

  // Query parameters
  static const String selectParam = 'select';
  static const String orderParam = 'order';
  static const String limitParam = 'limit';
  static const String offsetParam = 'offset';
  static const String rangeParam = 'Range';

  // Database operations
  static const String insertOperation = 'INSERT';
  static const String updateOperation = 'UPDATE';
  static const String deleteOperation = 'DELETE';
  static const String selectOperation = 'SELECT';

  // Log levels
  static const String logLevelError = 'ERROR';
  static const String logLevelWarn = 'WARN';
  static const String logLevelInfo = 'INFO';
  static const String logLevelDebug = 'DEBUG';

  // Function execution statuses
  static const String functionStatusSuccess = 'SUCCESS';
  static const String functionStatusError = 'ERROR';
  static const String functionStatusTimeout = 'TIMEOUT';

  // Project statuses
  static const String projectStatusActive = 'ACTIVE';
  static const String projectStatusInactive = 'INACTIVE';
  static const String projectStatusSuspended = 'SUSPENDED';
}