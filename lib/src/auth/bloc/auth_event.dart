/// Authentication events
sealed class AuthEvent {
  const AuthEvent();
}

// Email-first OTP-based authentication
class AuthSignUpWithEmailEvent extends AuthEvent {
  const AuthSignUpWithEmailEvent({
    required this.email,
    this.data,
  });

  final String email;
  final Map<String, dynamic>? data;
}

class AuthVerifySignUpEvent extends AuthEvent {
  const AuthVerifySignUpEvent({
    required this.email,
    required this.token,
    this.password,
  });

  final String email;
  final String token;
  final String? password;
}

class AuthSignInWithEmailEvent extends AuthEvent {
  const AuthSignInWithEmailEvent({
    required this.email,
  });

  final String email;
}

class AuthVerifySignInEvent extends AuthEvent {
  const AuthVerifySignInEvent({
    required this.email,
    required this.token,
  });

  final String email;
  final String token;
}

// Traditional email/password authentication
class AuthSignUpEvent extends AuthEvent {
  const AuthSignUpEvent({
    required this.email,
    required this.password,
    this.data,
  });

  final String email;
  final String password;
  final Map<String, dynamic>? data;
}

class AuthSignInWithPasswordEvent extends AuthEvent {
  const AuthSignInWithPasswordEvent({
    required this.email,
    required this.password,
  });

  final String email;
  final String password;
}

/// Complete an MFA-gated sign-in by exchanging the challenge token + a TOTP or
/// recovery code for a session.
class AuthVerifyMfaEvent extends AuthEvent {
  const AuthVerifyMfaEvent({
    required this.challengeToken,
    required this.code,
  });

  final String challengeToken;
  final String code;
}

// Session management
class AuthVerifySmsOtpEvent extends AuthEvent {
  const AuthVerifySmsOtpEvent({
    required this.phone,
    required this.code,
  });

  final String phone;
  final String code;
}

class AuthSignOutEvent extends AuthEvent {
  const AuthSignOutEvent();
}

class AuthRefreshSessionEvent extends AuthEvent {
  const AuthRefreshSessionEvent({
    this.refreshToken,
    this.silent = false,
  });

  final String? refreshToken;

  /// When true (cold-start refresh), a network failure emits nothing; the
  /// stored session is kept either way and refresh is retried on next use.
  final bool silent;
}

// User management
class AuthUpdateUserEvent extends AuthEvent {
  const AuthUpdateUserEvent({
    this.email,
    this.password,
    this.currentPassword,
    this.data,
  });

  final String? email;
  final String? password;

  /// Required by the server when changing [email] or [password].
  final String? currentPassword;
  final Map<String, dynamic>? data;
}

class AuthGetUserEvent extends AuthEvent {
  const AuthGetUserEvent();
}

// Password recovery
class AuthResetPasswordForEmailEvent extends AuthEvent {
  const AuthResetPasswordForEmailEvent({
    required this.email,
  });

  final String email;
}

class AuthUpdatePasswordEvent extends AuthEvent {
  const AuthUpdatePasswordEvent({
    required this.email,
    required this.token,
    required this.password,
  });

  final String email;
  final String token;
  final String password;
}

// Session initialization
class AuthInitializeEvent extends AuthEvent {
  const AuthInitializeEvent();
}

// Clear error state
class AuthClearErrorEvent extends AuthEvent {
  const AuthClearErrorEvent();
}

// ── Passkey / WebAuthn ──────────────────────────────────────────────────────

class AuthRegisterPasskeyEvent extends AuthEvent {
  const AuthRegisterPasskeyEvent({this.deviceName});
  final String? deviceName;
}

class AuthSignInWithPasskeyEvent extends AuthEvent {
  const AuthSignInWithPasskeyEvent({this.identifier});
  final String? identifier;
}

class AuthSignUpWithPasskeyEvent extends AuthEvent {
  const AuthSignUpWithPasskeyEvent({
    required this.email,
    this.userMetadata,
    this.deviceName,
  });
  final String email;
  final Map<String, dynamic>? userMetadata;
  final String? deviceName;
}

class AuthListPasskeysEvent extends AuthEvent {
  const AuthListPasskeysEvent();
}

class AuthRenamePasskeyEvent extends AuthEvent {
  const AuthRenamePasskeyEvent({
    required this.deviceId,
    required this.deviceName,
  });
  final String deviceId;
  final String deviceName;
}

class AuthRevokePasskeyEvent extends AuthEvent {
  const AuthRevokePasskeyEvent({required this.deviceId});
  final String deviceId;
}