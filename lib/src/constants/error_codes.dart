/// Error codes for NestCore exceptions
class ErrorCodes {
  // Network errors
  static const String connectionTimeout = 'CONNECTION_TIMEOUT';
  static const String sendTimeout = 'SEND_TIMEOUT';
  static const String receiveTimeout = 'RECEIVE_TIMEOUT';
  static const String connectionError = 'CONNECTION_ERROR';
  static const String badCertificate = 'BAD_CERTIFICATE';
  static const String requestCancelled = 'REQUEST_CANCELLED';
  static const String unknownError = 'UNKNOWN_ERROR';

  // HTTP status errors
  static const String badRequest = 'BAD_REQUEST';
  static const String unauthorized = 'UNAUTHORIZED';
  static const String forbidden = 'FORBIDDEN';
  static const String notFound = 'NOT_FOUND';
  static const String rateLimitExceeded = 'RATE_LIMIT_EXCEEDED';
  static const String internalServerError = 'INTERNAL_SERVER_ERROR';
  static const String badGateway = 'BAD_GATEWAY';
  static const String serviceUnavailable = 'SERVICE_UNAVAILABLE';
  static const String httpError = 'HTTP_ERROR';

  // Auth errors
  static const String invalidCredentials = 'INVALID_CREDENTIALS';
  static const String userNotFound = 'USER_NOT_FOUND';
  static const String emailNotConfirmed = 'EMAIL_NOT_CONFIRMED';
  static const String weakPassword = 'WEAK_PASSWORD';
  static const String emailAlreadyExists = 'EMAIL_ALREADY_EXISTS';
  static const String invalidToken = 'INVALID_TOKEN';
  static const String tokenExpired = 'TOKEN_EXPIRED';
  static const String signupDisabled = 'SIGNUP_DISABLED';
  static const String signinDisabled = 'SIGNIN_DISABLED';
  static const String operationTimeout = 'OPERATION_TIMEOUT';
  static const String responseParseError = 'RESPONSE_PARSE_ERROR';

  // Database errors
  static const String tableNotFound = 'TABLE_NOT_FOUND';
  static const String columnNotFound = 'COLUMN_NOT_FOUND';
  static const String invalidQuery = 'INVALID_QUERY';
  static const String permissionDenied = 'PERMISSION_DENIED';
  static const String constraintViolation = 'CONSTRAINT_VIOLATION';
  static const String rlsViolation = 'RLS_VIOLATION';

  // Function errors
  static const String functionNotFound = 'FUNCTION_NOT_FOUND';
  static const String functionExecutionError = 'FUNCTION_EXECUTION_ERROR';
  static const String functionTimeout = 'FUNCTION_TIMEOUT';

  // Project errors
  static const String projectNotFound = 'PROJECT_NOT_FOUND';
  static const String invalidApiKey = 'INVALID_API_KEY';
  static const String projectInactive = 'PROJECT_INACTIVE';

  // Passkey / WebAuthn errors
  static const String passkeyCancelled = 'PASSKEY_CANCELLED';
  static const String passkeyAlreadyExists = 'PASSKEY_ALREADY_EXISTS';
  static const String passkeyUnsupported = 'PASSKEY_UNSUPPORTED';
  static const String passkeyNotAvailable = 'PASSKEY_NOT_AVAILABLE';
  static const String passkeyDomainNotAssociated = 'PASSKEY_DOMAIN_NOT_ASSOCIATED';

  // Validation errors
  static const String validationError = 'VALIDATION_ERROR';
  static const String missingRequiredField = 'MISSING_REQUIRED_FIELD';
  static const String invalidEmail = 'INVALID_EMAIL';
  static const String invalidUuid = 'INVALID_UUID';

  // Project auth limits (429), set per project in NestCore → Settings → Auth Security
  static const String otpRateLimited = 'OTP_RATE_LIMITED'; // too many wrong codes
  static const String otpRequestLimit = 'OTP_REQUEST_LIMIT'; // too many codes requested for one email
  static const String accountLocked = 'ACCOUNT_LOCKED'; // too many wrong passwords
}
