import '../models/user.dart';
import '../models/session.dart';
import '../models/passkey_device.dart';

/// Authentication states
sealed class AuthState {
  const AuthState();
}

class AuthInitialState extends AuthState {
  const AuthInitialState();
}

class AuthLoadingState extends AuthState {
  const AuthLoadingState();
}

class AuthAuthenticatedState extends AuthState {
  const AuthAuthenticatedState({
    required this.user,
    required this.session,
  });

  final User user;
  final Session session;
}

class AuthUnauthenticatedState extends AuthState {
  const AuthUnauthenticatedState();
}

/// The password step succeeded but the account has a verified MFA factor, so a
/// second factor is required before a session is issued. Complete the sign-in
/// by calling `NestCoreAuth.verifyMfa(challengeToken:, code:)`.
class AuthMfaRequiredState extends AuthState {
  const AuthMfaRequiredState({
    required this.challengeToken,
    this.factors,
  });

  final String challengeToken;
  final List<dynamic>? factors;
}

class AuthOtpSentState extends AuthState {
  const AuthOtpSentState({
    required this.email,
    required this.message,
    this.type,
  });

  final String email;
  final String message;
  final String? type; // 'signup' or 'signin'
}

class AuthPasswordResetSentState extends AuthState {
  const AuthPasswordResetSentState({
    required this.email,
    required this.message,
  });

  final String email;
  final String message;
}

class AuthUserUpdatedState extends AuthState {
  const AuthUserUpdatedState({
    required this.user,
    this.message,
  });

  final User user;
  final String? message;
}

class AuthPasskeysListedState extends AuthState {
  const AuthPasskeysListedState({required this.devices});
  final List<PasskeyDevice> devices;
}

class AuthPasskeyRegisteredState extends AuthState {
  const AuthPasskeyRegisteredState({required this.device});
  final PasskeyDevice device;
}

class AuthPasskeyUpdatedState extends AuthState {
  const AuthPasskeyUpdatedState({
    required this.deviceId,
    required this.message,
  });
  final String deviceId;
  final String message;
}

class AuthPasskeyRevokedState extends AuthState {
  const AuthPasskeyRevokedState({required this.deviceId});
  final String deviceId;
}

class AuthErrorState extends AuthState {
  const AuthErrorState({
    required this.message,
    this.code,
    this.details,
  });

  final String message;
  final String? code;
  final Map<String, dynamic>? details;
}

/// Extension for AuthState to add convenience methods
extension AuthStateX on AuthState {
  bool get isAuthenticated => this is AuthAuthenticatedState;
  bool get isLoading => this is AuthLoadingState;
  bool get isError => this is AuthErrorState;
  bool get isUnauthenticated => this is AuthUnauthenticatedState;
  bool get isOtpSent => this is AuthOtpSentState;
  
  User? get user {
    return switch (this) {
      AuthAuthenticatedState(:final user) => user,
      AuthUserUpdatedState(:final user) => user,
      _ => null,
    };
  }
  
  Session? get session {
    return switch (this) {
      AuthAuthenticatedState(:final session) => session,
      _ => null,
    };
  }
  
  String? get error {
    return switch (this) {
      AuthErrorState(:final message) => message,
      _ => null,
    };
  }
  
  String? get errorCode {
    return switch (this) {
      AuthErrorState(:final code) => code,
      _ => null,
    };
  }
}