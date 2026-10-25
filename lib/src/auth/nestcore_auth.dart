import 'dart:async';
import 'package:flutter/foundation.dart';
import 'bloc/auth_bloc.dart';
import 'bloc/auth_event.dart';
import 'bloc/auth_state.dart';
import 'models/user.dart';
import 'models/session.dart';
import 'models/passkey_device.dart';
import 'exceptions/auth_exception.dart';
import 'services/auth_service.dart';
import 'services/token_manager.dart';
import 'services/passkey_authenticator_service.dart';

/// Simplified Auth API that wraps the BLoC pattern
/// Provides direct async methods like Supabase
class NestCoreAuth extends ChangeNotifier {
  final AuthBloc _authBloc;
  final AuthService _authService;
  final TokenManager _tokenManager;
  late final StreamSubscription _stateSubscription;

  AuthState _currentState = const AuthInitialState();
  final Map<String, Completer<dynamic>> _pendingOperations = {};
  Session? _lastKnownSession;

  NestCoreAuth(
    this._authBloc,
    this._authService,
    this._tokenManager,
  ) {
    _stateSubscription = _authBloc.stream.listen(_handleStateChange);
    _currentState = _authBloc.state;
  }

  void _handleStateChange(AuthState state) {
    _currentState = state;
    notifyListeners();

    // Cache the session whenever we enter an authenticated state so it remains
    // accessible even after transitioning to AuthUserUpdatedState (which carries
    // no session field of its own).
    if (state is AuthAuthenticatedState) {
      _lastKnownSession = state.session;
    }

    // Complete pending operations based on state changes
    switch (state) {
      case AuthAuthenticatedState(:final user, :final session):
        final result = {'user': user.toJson(), 'session': session.toJson()};
        for (final key in const ['auth_success', 'refresh', 'get_user']) {
          _completePendingOperation(key, result);
        }
        break;
      case AuthOtpSentState(:final email, :final message, :final type):
        _completePendingOperation('otp_sent', {
          'email': email,
          'message': message,
          'type': type,
        });
        break;
      case AuthPasswordResetSentState(:final email, :final message):
        _completePendingOperation('password_reset_sent', {
          'email': email,
          'message': message,
        });
        break;
      case AuthUserUpdatedState(:final user, :final message):
        _completePendingOperation('user_updated', {
          'user': user.toJson(),
          'message': message,
        });
        break;
      case AuthUnauthenticatedState():
        _completePendingOperation('unauthenticated', null);
        // refreshSession()/getUser() would otherwise wait forever.
        const notSignedIn = AuthException('Not signed in or session expired',
            code: 'UNAUTHENTICATED', statusCode: 401);
        _completePendingOperationWithError('refresh', notSignedIn);
        _completePendingOperationWithError('get_user', notSignedIn);
        break;
      case AuthMfaRequiredState(:final challengeToken, :final factors):
        // Resolve the pending signInWithPassword with the challenge instead of
        // throwing — the caller checks `mfa_required` and follows up with
        // verifyMfa(challengeToken:, code:).
        _completePendingOperation('auth_success', {
          'mfa_required': true,
          'challenge_token': challengeToken,
          'factors': factors,
        });
        break;
      case AuthPasskeyRegisteredState(:final device):
        _completePendingOperation('passkey_registered', device.toJson());
        break;
      case AuthPasskeysListedState(:final devices):
        _completePendingOperation('passkeys_listed', devices);
        break;
      case AuthPasskeyUpdatedState():
        _completePendingOperation('passkey_updated', null);
        break;
      case AuthPasskeyRevokedState():
        _completePendingOperation('passkey_revoked', null);
        break;
      case AuthErrorState(:final message, :final code):
        // Complete all pending operations with the error
        final error = AuthException(message, code: code);
        final pendingKeys = List<String>.from(_pendingOperations.keys);
        for (final key in pendingKeys) {
          _completePendingOperationWithError(key, error);
        }
        break;
      case AuthInitialState():
        break;
      case AuthLoadingState():
        break;
    }
  }

  void _completePendingOperation(String key, dynamic result) {
    final completer = _pendingOperations.remove(key);
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  void _completePendingOperationWithError(String key, Object error) {
    final completer = _pendingOperations.remove(key);
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
    }
  }

  Future<T> _executeWithCompleter<T>(
    String operationKey,
    AuthEvent event,
  ) async {
    final completer = Completer<T>();
    _pendingOperations[operationKey] = completer;

    _authBloc.add(event);

    // No manual timeout - rely only on Dio client timeout
    return completer.future;
  }

  /// Get current user (null only when explicitly unauthenticated).
  ///
  /// Transient states (AuthPasskeysListedState, AuthLoadingState, etc.) do
  /// NOT clear the user — they fall back to [_lastKnownSession]?.user so
  /// callers always see the authenticated user while background operations
  /// are in flight.
  User? get currentUser {
    return switch (_currentState) {
      AuthAuthenticatedState(:final user) => user,
      AuthUserUpdatedState(:final user) => user,
      AuthUnauthenticatedState() => null,
      _ => _lastKnownSession?.user,
    };
  }

  /// Get current session (null only when explicitly unauthenticated).
  ///
  /// Transient states (AuthPasskeysLoaded, AuthPasskeyRegisteredState,
  /// AuthLoadingState, etc.) do NOT clear the session — they return
  /// [_lastKnownSession] so callers like refreshCurrentUser() can still
  /// read the access token while a transient operation is in flight.
  Session? get currentSession {
    return switch (_currentState) {
      AuthAuthenticatedState(:final session) => session,
      AuthUnauthenticatedState() => null,
      _ => _lastKnownSession,
    };
  }

  /// Check if user is currently authenticated.
  ///
  /// Transient states do NOT clear authentication — only an explicit
  /// [AuthUnauthenticatedState] means the user has signed out.
  bool get isAuthenticated {
    return switch (_currentState) {
      AuthAuthenticatedState() => true,
      AuthUserUpdatedState() => true,
      AuthUnauthenticatedState() => false,
      _ => _lastKnownSession != null,
    };
  }

  /// Get current auth state for UI reactivity
  AuthState get state => _currentState;

  /// Stream of auth state changes for listening to auth events
  Stream<AuthState> get onAuthStateChange => _authBloc.stream;

  /// Sign up with email (OTP-based flow)
  /// Returns a map with email and message when OTP is sent
  Future<Map<String, dynamic>> signUpWithEmail(
    String email, {
    Map<String, dynamic>? metadata,
  }) async {
    return await _executeWithCompleter<Map<String, dynamic>>(
      'otp_sent',
      AuthSignUpWithEmailEvent(email: email, data: metadata),
    );
  }

  /// Verify email signup with OTP
  /// Returns user and session when successful
  Future<Map<String, dynamic>> verifySignUp({
    required String email,
    required String otp,
    String? password,
  }) async {
    return await _executeWithCompleter<Map<String, dynamic>>(
      'auth_success',
      AuthVerifySignUpEvent(email: email, token: otp, password: password),
    );
  }

  /// Sign in with email (OTP-based flow)
  /// Returns a map with email and message when OTP is sent
  Future<Map<String, dynamic>> signInWithEmail(String email) async {
    return await _executeWithCompleter<Map<String, dynamic>>(
      'otp_sent',
      AuthSignInWithEmailEvent(email: email),
    );
  }

  /// Verify email signin with OTP
  /// Returns user and session when successful
  Future<Map<String, dynamic>> verifySignIn({
    required String email,
    required String otp,
  }) async {
    return await _executeWithCompleter<Map<String, dynamic>>(
      'auth_success',
      AuthVerifySignInEvent(email: email, token: otp),
    );
  }

  /// Traditional signup with email and password
  /// Returns email and message when OTP is sent for verification
  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? metadata,
  }) async {
    return await _executeWithCompleter<Map<String, dynamic>>(
      'otp_sent',
      AuthSignUpEvent(email: email, password: password, data: metadata),
    );
  }

  /// Traditional signin with email and password.
  ///
  /// Returns `{ user, session }` when successful. If the account has a verified
  /// MFA factor, instead returns `{ mfa_required: true, challenge_token, factors }`
  /// (no session) — pass the `challenge_token` to [verifyMfa] with a TOTP or
  /// recovery code to finish signing in:
  /// ```dart
  /// final res = await auth.signInWithPassword(email: e, password: p);
  /// if (res['mfa_required'] == true) {
  ///   await auth.verifyMfa(challengeToken: res['challenge_token'], code: code);
  /// }
  /// ```
  Future<Map<String, dynamic>> signInWithPassword({
    required String email,
    required String password,
  }) async {
    return await _executeWithCompleter<Map<String, dynamic>>(
      'auth_success',
      AuthSignInWithPasswordEvent(email: email, password: password),
    );
  }

  /// Send password recovery email
  /// Returns a map with email and message when email is sent
  Future<Map<String, dynamic>> resetPasswordForEmail(String email) async {
    return await _executeWithCompleter<Map<String, dynamic>>(
      'password_reset_sent',
      AuthResetPasswordForEmailEvent(email: email),
    );
  }

  /// Reset password with the code from the recovery email.
  /// Returns `{email, message}`; the user then signs in with the new password.
  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    return await _executeWithCompleter<Map<String, dynamic>>(
      'password_reset_sent',
      AuthUpdatePasswordEvent(
        email: email,
        token: token,
        password: newPassword,
      ),
    );
  }

  /// Update current user profile.
  /// Changing [email] or [password] requires [currentPassword] (accounts
  /// without a password instead need a session less than 10 minutes old);
  /// otherwise the server answers 401 `REAUTH_REQUIRED`.
  /// Returns updated user when successful
  Future<Map<String, dynamic>> updateUser({
    String? email,
    String? password,
    String? currentPassword,
    Map<String, dynamic>? metadata,
  }) async {
    return await _executeWithCompleter<Map<String, dynamic>>(
      'user_updated',
      AuthUpdateUserEvent(
        email: email,
        password: password,
        currentPassword: currentPassword,
        data: metadata,
      ),
    );
  }

  /// Apply a pending email change (requested with [updateUser]) using the code
  /// sent to the new address. The access token keeps the old `email` claim
  /// until the next refresh.
  Future<Map<String, dynamic>> verifyEmailChange(String code) async {
    try {
      return await _authService.verifyEmailChange(code);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException.fromException(e);
    }
  }

  /// Permanently delete the signed-in user's account, then clear the local
  /// session (auth state becomes unauthenticated).
  Future<void> deleteUser() async {
    try {
      await _authService.deleteUser();
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException.fromException(e);
    }
    await _tokenManager.clearSession();
    _authBloc.add(const AuthInitializeEvent()); // no stored session → unauthenticated
  }

  /// Refresh current session.
  /// Returns user and session when successful. Throws [AuthException] when the
  /// session is gone (`UNAUTHENTICATED`) or the server could not be reached
  /// (`REFRESH_FAILED` — the stored session is kept).
  Future<Map<String, dynamic>> refreshSession() async {
    final result = await _executeWithCompleter<Map<String, dynamic>>(
      'refresh',
      const AuthRefreshSessionEvent(),
    );
    // Update this TokenManager's in-memory cache directly after a successful
    // refresh. The AuthBloc's own storeSession() call may have targeted a
    // different TokenManager instance (custom DI setups where AuthBloc and
    // NestCoreAuth are wired separately), so we call it here too — idempotent
    // when they share the same instance.
    try {
      final raw = result['session'];
      if (raw is Map<String, dynamic>) {
        await _tokenManager.storeSession(Session.fromJson(raw));
      }
    } catch (_) {}
    return result;
  }

  /// Sign out current user
  /// Returns when signout is complete
  Future<void> signOut() async {
    await _executeWithCompleter<void>(
      'unauthenticated',
      const AuthSignOutEvent(),
    );
  }

  /// Get current user profile
  /// Returns user when successful, throws if not authenticated
  Future<User> getUser() async {
    if (currentUser != null) {
      return currentUser!;
    }

    // Trigger getUser event and wait for result
    final result = await _executeWithCompleter<Map<String, dynamic>>(
      'get_user',
      const AuthGetUserEvent(),
    );

    return User.fromJson(Map<String, dynamic>.from(result['user'] as Map));
  }

  // ── Passkey / WebAuthn ────────────────────────────────────────────────────

  PasskeyAuthenticatorService get _passkeyAuth {
    return _passkeyAuthenticator ??= PasskeyAuthenticatorService();
  }

  PasskeyAuthenticatorService? _passkeyAuthenticator;

  /// True if the platform exposes any passkey authenticator (Touch/Face ID,
  /// device PIN, security key, etc.).
  Future<bool> isPasskeySupported() => _passkeyAuth.isAvailable();

  /// Register a new passkey for the currently authenticated user.
  /// Drives the native registration ceremony and posts the attestation back
  /// to the NestCore server.
  Future<PasskeyDevice> registerPasskey({String? deviceName}) async {
    final result = await _executeWithCompleter<Map<String, dynamic>>(
      'passkey_registered',
      AuthRegisterPasskeyEvent(deviceName: deviceName),
    );
    return PasskeyDevice.fromJson(result);
  }

  /// Sign up a new account using a passkey in a single ceremony.
  /// Only [email] is required; [userMetadata] and [deviceName] are optional.
  Future<Map<String, dynamic>> signUpWithPasskey({
    required String email,
    Map<String, dynamic>? userMetadata,
    String? deviceName,
  }) async {
    return await _executeWithCompleter<Map<String, dynamic>>(
      'auth_success',
      AuthSignUpWithPasskeyEvent(
        email: email,
        userMetadata: userMetadata,
        deviceName: deviceName,
      ),
    );
  }

  /// Sign in using a passkey. Drives the native assertion ceremony and stores
  /// the resulting session.
  Future<Map<String, dynamic>> signInWithPasskey({String? identifier}) async {
    return await _executeWithCompleter<Map<String, dynamic>>(
      'auth_success',
      AuthSignInWithPasskeyEvent(identifier: identifier),
    );
  }

  /// List all registered passkeys for the current user.
  Future<List<PasskeyDevice>> listPasskeys() async {
    return await _executeWithCompleter<List<PasskeyDevice>>(
      'passkeys_listed',
      const AuthListPasskeysEvent(),
    );
  }

  /// Rename a registered passkey.
  Future<void> renamePasskey({
    required String deviceId,
    required String deviceName,
  }) async {
    await _executeWithCompleter<void>(
      'passkey_updated',
      AuthRenamePasskeyEvent(deviceId: deviceId, deviceName: deviceName),
    );
  }

  /// Revoke (remove) a registered passkey.
  Future<void> revokePasskey({required String deviceId}) async {
    await _executeWithCompleter<void>(
      'passkey_revoked',
      AuthRevokePasskeyEvent(deviceId: deviceId),
    );
  }

  /// Verify a JWT token against the server (ON-SEC-04)
  /// Returns a map with valid, user, and error fields from the API
  Future<Map<String, dynamic>> verifyToken(String token) async {
    try {
      return await _authService.verifyToken(token);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException.fromException(e);
    }
  }

  /// Decode a JWT token locally without a network call (ON-SEC-06)
  /// Returns the token payload, or null if the token is malformed
  Map<String, dynamic>? decodeToken(String token) {
    return _tokenManager.decodeToken(token);
  }

  // ─── SMS OTP (phone sign-in; project must have Twilio configured) ───

  /// Send a one-time code to a phone number (E.164, e.g. `+15555550123`).
  /// Rate limited per phone: `AuthException` code `SMS_RATE_LIMITED` (429).
  Future<Map<String, dynamic>> signInWithSms(String phone) async {
    try {
      return await _authService.signInWithSms(phone: phone);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException.fromException(e);
    }
  }

  /// Verify a phone OTP and sign in (creates the user on first sign-in).
  /// Returns `{user, session}` and updates auth state like a password sign-in.
  /// Too many attempts → `AuthException` with code `OTP_RATE_LIMITED` (429).
  Future<Map<String, dynamic>> verifySmsOtp({
    required String phone,
    required String code,
  }) async {
    return await _executeWithCompleter<Map<String, dynamic>>(
      'auth_success',
      AuthVerifySmsOtpEvent(phone: phone, code: code),
    );
  }

  // ─── MFA (TOTP / authenticator apps) ───

  /// Begin TOTP enrollment — returns `secret`, `otpauth_url`, `qr_code`, `factor_id`.
  /// When the user already has a verified factor, pass a current TOTP or
  /// recovery [code] (server answers 401 `MFA_REAUTH_REQUIRED` otherwise).
  Future<Map<String, dynamic>> enrollMfaTotp({String? friendlyName, String? code}) async {
    try {
      return await _authService.enrollMfaTotp(friendlyName: friendlyName, code: code);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException.fromException(e);
    }
  }

  /// Confirm a TOTP enrollment with the first code from the authenticator.
  /// On success the result includes `recovery_codes` (shown once).
  Future<Map<String, dynamic>> verifyMfaEnrollment({
    required String factorId,
    required String code,
  }) async {
    try {
      return await _authService.verifyMfaEnrollment(factorId: factorId, code: code);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException.fromException(e);
    }
  }

  /// Regenerate the user's MFA recovery codes. Returns `{ codes: [...] }` once.
  /// Requires a current TOTP or recovery [code] when MFA is active.
  Future<Map<String, dynamic>> regenerateMfaRecoveryCodes({String? code}) async {
    try {
      return await _authService.regenerateMfaRecoveryCodes(code: code);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException.fromException(e);
    }
  }

  /// List the current user's MFA factors.
  Future<List<dynamic>> listMfaFactors() async {
    try {
      return await _authService.listMfaFactors();
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException.fromException(e);
    }
  }

  /// Remove an MFA factor. Requires a current TOTP or recovery [code] when
  /// the user has a verified factor.
  Future<void> unenrollMfa({required String factorId, String? code}) async {
    try {
      await _authService.unenrollMfa(factorId: factorId, code: code);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException.fromException(e);
    }
  }

  /// Complete an MFA-gated sign-in. When `signInWithPassword` returns an
  /// `mfa_required` challenge, call this with its `challenge_token` and a TOTP
  /// code. Stores the resulting session.
  Future<Map<String, dynamic>> verifyMfa({
    required String challengeToken,
    required String code,
  }) async {
    // Route through the BLoC so a successful verify transitions auth state to
    // AuthAuthenticatedState — updating isAuthenticated, currentUser/currentSession,
    // and the onAuthStateChange stream — exactly like a password sign-in.
    return await _executeWithCompleter<Map<String, dynamic>>(
      'auth_success',
      AuthVerifyMfaEvent(challengeToken: challengeToken, code: code),
    );
  }

  @override
  void dispose() {
    _stateSubscription.cancel();
    super.dispose();
  }
}
