import '../services/auth_service.dart';
import '../models/auth_response.dart';
import '../models/user.dart';
import '../exceptions/auth_exception.dart';

/// Repository for authentication operations
/// Provides a layer of abstraction between the BLoC and the service
class AuthRepository {
  final AuthService _authService;

  AuthRepository({
    required AuthService authService,
  }) : _authService = authService;

  /// Sign up with email (OTP-based)
  Future<AuthResponse> signUpWithEmail({
    required String email,
    Map<String, dynamic>? data,
  }) async {
    try {
      return await _authService.signUpWithEmail(
        email: email,
        data: data,
      );
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Verify signup with OTP
  Future<AuthResponse> verifySignUp({
    required String email,
    required String token,
    String? password,
  }) async {
    try {
      return await _authService.verifySignUp(
        email: email,
        token: token,
        password: password,
      );
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Sign in with email (OTP-based)
  Future<AuthResponse> signInWithEmail({
    required String email,
  }) async {
    try {
      return await _authService.signInWithEmail(email: email);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Verify signin with OTP
  Future<AuthResponse> verifySignIn({
    required String email,
    required String token,
  }) async {
    try {
      return await _authService.verifySignIn(
        email: email,
        token: token,
      );
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Traditional sign up with email and password
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  }) async {
    try {
      return await _authService.signUp(
        email: email,
        password: password,
        data: data,
      );
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Traditional sign in with email and password
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      return await _authService.signInWithPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Complete an MFA-gated sign-in with the challenge token + TOTP/recovery code.
  Future<AuthResponse> verifyMfa({
    required String challengeToken,
    required String code,
  }) async {
    try {
      return await _authService.verifyMfa(
        challengeToken: challengeToken,
        code: code,
      );
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Verify a phone OTP and sign in.
  Future<AuthResponse> verifySmsOtp({
    required String phone,
    required String code,
  }) async {
    try {
      return await _authService.verifySmsOtp(phone: phone, code: code);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Sign out the current user
  Future<void> signOut() async {
    try {
      await _authService.signOut();
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Refresh the current session
  Future<AuthResponse> refreshSession({
    required String refreshToken,
  }) async {
    try {
      return await _authService.refreshSession(refreshToken: refreshToken);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Get current user
  Future<User?> getUser() async {
    try {
      return await _authService.getUser();
    } catch (e) {
      // Return null if user is not authenticated
      if (e is AuthException && e.statusCode == 401) {
        return null;
      }
      throw AuthException.fromException(e);
    }
  }

  /// Update current user
  Future<UserUpdateResponse> updateUser({
    String? email,
    String? password,
    String? currentPassword,
    Map<String, dynamic>? data,
  }) async {
    try {
      return await _authService.updateUser(
        email: email,
        password: password,
        currentPassword: currentPassword,
        data: data,
      );
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Request password reset
  Future<PasswordResetResponse> resetPasswordForEmail({
    required String email,
  }) async {
    try {
      return await _authService.resetPasswordForEmail(email: email);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Update password with reset token
  Future<AuthResponse> updatePassword({
    required String email,
    required String token,
    required String password,
  }) async {
    try {
      return await _authService.updatePassword(
        email: email,
        token: token,
        password: password,
      );
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  // ── Passkey / WebAuthn ────────────────────────────────────────────────────

  Future<Map<String, dynamic>> passkeyRegisterOptions({String? deviceName}) async {
    try {
      return await _authService.passkeyRegisterOptions(deviceName: deviceName);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  Future<Map<String, dynamic>> passkeyRegisterVerify({
    required String challengeId,
    required Map<String, dynamic> attestation,
    String? deviceName,
  }) async {
    try {
      return await _authService.passkeyRegisterVerify(
        challengeId: challengeId,
        attestation: attestation,
        deviceName: deviceName,
      );
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  Future<Map<String, dynamic>> passkeySignupOptions({
    required String email,
    Map<String, dynamic>? userMetadata,
    String? deviceName,
  }) async {
    try {
      return await _authService.passkeySignupOptions(
        email: email,
        userMetadata: userMetadata,
        deviceName: deviceName,
      );
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  Future<AuthResponse> passkeySignupVerify({
    required String challengeId,
    required Map<String, dynamic> attestation,
    String? deviceName,
  }) async {
    try {
      return await _authService.passkeySignupVerify(
        challengeId: challengeId,
        attestation: attestation,
        deviceName: deviceName,
      );
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  Future<Map<String, dynamic>> passkeyLoginOptions({String? identifier}) async {
    try {
      return await _authService.passkeyLoginOptions(identifier: identifier);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  Future<AuthResponse> passkeyLoginVerify({
    required String challengeId,
    required Map<String, dynamic> assertion,
  }) async {
    try {
      return await _authService.passkeyLoginVerify(
        challengeId: challengeId,
        assertion: assertion,
      );
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  Future<List<Map<String, dynamic>>> listPasskeys() async {
    try {
      return await _authService.listPasskeys();
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  Future<Map<String, dynamic>> renamePasskey({
    required String deviceId,
    required String deviceName,
  }) async {
    try {
      return await _authService.renamePasskey(
        deviceId: deviceId,
        deviceName: deviceName,
      );
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  Future<void> revokePasskey({required String deviceId}) async {
    try {
      await _authService.revokePasskey(deviceId: deviceId);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }
}