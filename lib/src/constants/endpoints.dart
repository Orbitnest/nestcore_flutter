/// API endpoint constants for NestCore
class Endpoints {
  // Admin Authentication
  static const String adminRequestVerification =
      '/api/auth/request-verification';
  static const String adminSignup = '/api/auth/signup';
  static const String adminSignin = '/api/auth/signin';
  static const String adminProfile = '/api/auth/profile';
  static const String adminRequestPasswordReset =
      '/api/auth/reset-password-request';
  static const String adminResetPassword = '/api/auth/reset-password';
  static const String adminChangePassword = '/api/auth/change-password';
  static const String adminRefreshToken = '/api/auth/refresh';
  static const String adminSignout = '/api/auth/signout';

  // Admin User Management
  static const String adminUsers = '/api/admin/admins';
  static String adminUserById(String id) => '/api/admin/admins/$id';
  static String adminUpdatePassword(String id) =>
      '/api/admin/admins/$id/password';
  static const String adminApiKeys = '/api/admin/api-keys';
  static String adminApiKeyById(String id) => '/api/admin/api-keys/$id';

  // Project Management
  static const String projects = '/api/projects';
  static String projectById(String id) => '/api/projects/$id';
  static String projectApiKeys(String id) => '/api/projects/$id/api-keys';
  static String deleteProjectApiKey(String projectId, String keyId) =>
      '/api/projects/$projectId/api-keys/$keyId';
  static String projectDecryptionKey(String projectId) => '/api/projects/$projectId/api-keys/decrypted';

  // Project API Key Authentication
  static String projectInfo(String slug) => '/api/project/$slug/info';
  static String projectHealth(String slug) => '/api/project/$slug/health';
  static String projectTestAuth(String slug) => '/api/project/$slug/test-auth';

  // Project Authentication
  static String projectSignupWithEmail(String projectId) =>
      '/api/projects/$projectId/auth/signup-with-email';
  static String projectVerifySignup(String projectId) =>
      '/api/projects/$projectId/auth/verify-signup';
  static String projectSigninWithEmail(String projectId) =>
      '/api/projects/$projectId/auth/signin-with-email';
  static String projectVerifySignin(String projectId) =>
      '/api/projects/$projectId/auth/verify-signin';
  static String projectSignup(String projectId) =>
      '/api/projects/$projectId/auth/signup';
  static String projectSignin(String projectId) =>
      '/api/projects/$projectId/auth/signin';
  static String projectRecover(String projectId) =>
      '/api/projects/$projectId/auth/recover';
  static String projectResetPassword(String projectId) =>
      '/api/projects/$projectId/auth/reset-password';
  static String projectUser(String projectId) =>
      '/api/projects/$projectId/auth/user';
  static String projectVerifyEmailChange(String projectId) =>
      '/api/projects/$projectId/auth/user/email/verify';
  static String projectUpdateUser(String projectId) =>
      '/api/projects/$projectId/auth/user';
  static String projectDeleteUser(String projectId) =>
      '/api/projects/$projectId/auth/user';
  static String projectRefresh(String projectId) =>
      '/api/projects/$projectId/auth/refresh';
  static String projectSignout(String projectId) =>
      '/api/projects/$projectId/auth/signout';
  static String projectSignoutAll(String projectId) =>
      '/api/projects/$projectId/auth/signout-all';
  static String projectVerifyToken(String projectId) =>
      '/api/projects/$projectId/auth/verify';

  // SMS OTP (phone sign-in via the project's own Twilio)
  static String projectSmsSendOtp(String projectId) =>
      '/api/projects/$projectId/auth/sms/send-otp';
  static String projectSmsVerifyOtp(String projectId) =>
      '/api/projects/$projectId/auth/sms/verify-otp';

  // MFA (TOTP / authenticator apps)
  static String projectVerifyMfa(String projectId) =>
      '/api/projects/$projectId/auth/verify-mfa';
  static String projectMfaEnroll(String projectId) =>
      '/api/projects/$projectId/auth/mfa/totp/enroll';
  static String projectMfaVerifyEnroll(String projectId) =>
      '/api/projects/$projectId/auth/mfa/totp/verify';
  static String projectMfaFactors(String projectId) =>
      '/api/projects/$projectId/auth/mfa/factors';
  static String projectMfaFactor(String projectId, String factorId) =>
      '/api/projects/$projectId/auth/mfa/factors/$factorId';
  static String projectMfaRecoveryCodes(String projectId) =>
      '/api/projects/$projectId/auth/mfa/recovery-codes';

  // Passkey (WebAuthn) — project-user realm
  static String projectPasskeyRegisterOptions(String projectId) =>
      '/api/projects/$projectId/auth/passkey/register/options';
  static String projectPasskeyRegisterVerify(String projectId) =>
      '/api/projects/$projectId/auth/passkey/register/verify';
  static String projectPasskeySignupOptions(String projectId) =>
      '/api/projects/$projectId/auth/passkey/signup/options';
  static String projectPasskeySignupVerify(String projectId) =>
      '/api/projects/$projectId/auth/passkey/signup/verify';
  static String projectPasskeyLoginOptions(String projectId) =>
      '/api/projects/$projectId/auth/passkey/login/options';
  static String projectPasskeyLoginVerify(String projectId) =>
      '/api/projects/$projectId/auth/passkey/login/verify';
  static String projectPasskeyDevices(String projectId) =>
      '/api/projects/$projectId/auth/passkey/devices';
  static String projectPasskeyDevice(String projectId, String deviceId) =>
      '/api/projects/$projectId/auth/passkey/devices/$deviceId';

  // Admin Project Auth
  static String projectAdminUsers(String projectId) =>
      '/api/projects/$projectId/auth/admin/users';
  static String projectAdminUserById(String projectId, String userId) =>
      '/api/projects/$projectId/auth/admin/users/$userId';
  static String projectAdminStats(String projectId) =>
      '/api/projects/$projectId/auth/admin/stats';

  // Edge Functions
  static String projectFunctions(String projectId) =>
      '/api/projects/$projectId/functions';
  static String projectFunctionByName(String projectId, String name) =>
      '/api/projects/$projectId/functions/$name';
  static String projectFunctionLogs(String projectId, String name) =>
      '/api/projects/$projectId/functions/$name/logs';

  // Function Invocation
  static String invokeFunction(String projectSlug, String name) =>
      '/api/projects/$projectSlug/functions/v1/$name';

  // Environment Variables
  static String projectEnvironmentVariables(String projectId) =>
      '/api/projects/$projectId/environment-variables';
  static String projectEnvironmentVariablesBulk(String projectId) =>
      '/api/projects/$projectId/environment-variables/bulk';
  static String projectEnvironmentVariableByName(
          String projectId, String name) =>
      '/api/projects/$projectId/environment-variables/$name';

  // Database Operations (Client endpoints using project slug)
  static String projectDatabaseSql(String projectSlug) =>
      '/api/project/$projectSlug/database/sql';
  static String projectDatabaseSemantic(String projectSlug) =>
      '/api/project/$projectSlug/database/semantic';
  static String projectDatabaseTables(String projectSlug) =>
      '/api/project/$projectSlug/database/tables';
  static String projectDatabaseTablesList(String projectSlug) =>
      '/api/project/$projectSlug/database/tables/list';
  static String projectDatabaseTableData(String projectSlug, String table) =>
      '/api/project/$projectSlug/database/tables/$table/data';
  static String projectDatabaseTableRows(String projectSlug, String table) =>
      '/api/project/$projectSlug/database/tables/$table/rows';
  static String projectDatabaseTableRowById(
          String projectSlug, String table, String rowId) =>
      '/api/project/$projectSlug/database/tables/$table/rows/$rowId';
  static String projectDatabaseTableBulkInsert(
          String projectSlug, String table) =>
      '/api/project/$projectSlug/database/tables/$table/rows/bulk';
  static String projectDatabaseTableBulkUpdate(
          String projectSlug, String table) =>
      '/api/project/$projectSlug/database/tables/$table/rows/bulk';
  static String projectDatabaseTableBulkDelete(
          String projectSlug, String table) =>
      '/api/project/$projectSlug/database/tables/$table/rows/bulk';
  static String projectDatabaseTableEnableRls(String projectSlug, String table) =>
      '/api/project/$projectSlug/database/tables/$table/rls/enable';
  static String projectDatabaseTableDisableRls(
          String projectSlug, String table) =>
      '/api/project/$projectSlug/database/tables/$table/rls/disable';
  static String projectDatabaseTablePolicies(String projectSlug, String table) =>
      '/api/project/$projectSlug/database/tables/$table/policies';
  static String projectDatabaseTablePolicyByName(
          String projectSlug, String table, String name) =>
      '/api/project/$projectSlug/database/tables/$table/policies/$name';

  // Logging
  static String projectLogs(String projectId) =>
      '/api/projects/$projectId/logs';
  static String projectDatabaseLogs(String projectId) =>
      '/api/projects/$projectId/logs/database';
  static String projectDatabaseSlowLogs(String projectId) =>
      '/api/projects/$projectId/logs/database/slow';
  static String projectDatabaseErrorLogs(String projectId) =>
      '/api/projects/$projectId/logs/database/errors';
  static String projectAuthLogs(String projectId) =>
      '/api/projects/$projectId/logs/auth';
  static String projectAuthFailureLogs(String projectId) =>
      '/api/projects/$projectId/logs/auth/failures';
  static String projectSecurityLogs(String projectId) =>
      '/api/projects/$projectId/logs/auth/security';
  static String projectEdgeFunctionLogs(String projectId) =>
      '/api/projects/$projectId/logs/edge-functions';
  static String projectEdgeFunctionConsoleLogs(
          String projectId, String functionName) =>
      '/api/projects/$projectId/logs/edge-functions/$functionName/console';
  static String projectEdgeFunctionErrorLogs(
          String projectId, String functionName) =>
      '/api/projects/$projectId/logs/edge-functions/$functionName/errors';
  static String projectExportLogs(String projectId) =>
      '/api/projects/$projectId/logs/export';

  // Background Jobs
  static String projectJobs(String projectId) =>
      '/api/projects/$projectId/jobs';
  static String projectJobByName(String projectId, String name) =>
      '/api/projects/$projectId/jobs/$name';
  static String projectJobTrigger(String projectId, String name) =>
      '/api/projects/$projectId/jobs/$name/trigger';
  static String projectJobRuns(String projectId, String name) =>
      '/api/projects/$projectId/jobs/$name/runs';

  // Database Migrations (server-side runner)
  static String projectMigrationsRun(String projectSlug) =>
      '/api/project/$projectSlug/migrations/run';
  static String projectMigrationsStatus(String projectSlug) =>
      '/api/project/$projectSlug/migrations/status';

  // Health Checks
  static const String databaseHealth = '/api/database/health';
}
