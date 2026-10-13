import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../repositories/auth_repository.dart';
import '../services/token_manager.dart';
import '../services/passkey_authenticator_service.dart';
import '../models/passkey_device.dart';
import '../models/session.dart';
import '../exceptions/auth_exception.dart';
import 'auth_event.dart';
import 'auth_state.dart';

/// BLoC for managing authentication state
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;
  final TokenManager _tokenManager;
  final PasskeyAuthenticatorService _passkeyAuthenticator;

  AuthBloc({
    required AuthRepository authRepository,
    required TokenManager tokenManager,
    PasskeyAuthenticatorService? passkeyAuthenticator,
  })  : _authRepository = authRepository,
        _tokenManager = tokenManager,
        _passkeyAuthenticator =
            passkeyAuthenticator ?? PasskeyAuthenticatorService(),
        super(const AuthInitialState()) {
    // Register event handlers
    on<AuthSignUpWithEmailEvent>(_onSignUpWithEmail);
    on<AuthVerifySignUpEvent>(_onVerifySignUp);
    on<AuthSignInWithEmailEvent>(_onSignInWithEmail);
    on<AuthVerifySignInEvent>(_onVerifySignIn);
    on<AuthSignUpEvent>(_onSignUp);
    on<AuthSignInWithPasswordEvent>(_onSignInWithPassword);
    on<AuthVerifyMfaEvent>(_onVerifyMfa);
    on<AuthVerifySmsOtpEvent>(_onVerifySmsOtp);
    on<AuthSignOutEvent>(_onSignOut);
    on<AuthRefreshSessionEvent>(_onRefreshSession);
    on<AuthUpdateUserEvent>(_onUpdateUser);
    on<AuthGetUserEvent>(_onGetUser);
    on<AuthResetPasswordForEmailEvent>(_onResetPasswordForEmail);
    on<AuthUpdatePasswordEvent>(_onUpdatePassword);
    on<AuthInitializeEvent>(_onInitialize);
    on<AuthClearErrorEvent>(_onClearError);
    on<AuthRegisterPasskeyEvent>(_onRegisterPasskey);
    on<AuthSignInWithPasskeyEvent>(_onSignInWithPasskey);
    on<AuthSignUpWithPasskeyEvent>(_onSignUpWithPasskey);
    on<AuthListPasskeysEvent>(_onListPasskeys);
    on<AuthRenamePasskeyEvent>(_onRenamePasskey);
    on<AuthRevokePasskeyEvent>(_onRevokePasskey);

    // Register refresh callback with token manager
    _tokenManager.setRefreshCallback(_performTokenRefresh);

    // Initialize authentication state
    add(const AuthInitializeEvent());
  }

  /// Perform token refresh for token manager callback
  ///
  /// Returns false only when there is no refresh token or the server rejected
  /// it (4xx). Network errors, timeouts, 408/429 and 5xx are rethrown so the
  /// TokenManager reports them as transient and the stored session is kept.
  Future<bool> _performTokenRefresh() async {
    final refreshToken = await _tokenManager.getRefreshToken();
    if (refreshToken == null) {
      return false;
    }

    try {
      final response = await _authRepository.refreshSession(
        refreshToken: refreshToken,
      );

      if (response.isAuthenticated && response.session != null) {
        await _tokenManager.storeSession(response.session!);
        return true;
      }

      return false;
    } on AuthException catch (e) {
      final status = e.statusCode;
      if (status != null && status >= 400 && status < 500 && status != 408 && status != 429) {
        return false;
      }
      rethrow;
    }
  }

  Future<void> _onSignUpWithEmail(
    AuthSignUpWithEmailEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoadingState());

    try {
      final response = await _authRepository.signUpWithEmail(
        email: event.email,
        data: event.data,
      );

      if (response.isOtpSent) {
        emit(
          AuthOtpSentState(
            email: event.email,
            message: response.message ?? 'OTP sent to your email',
            type: 'signup',
          ),
        );
      } else if (response.isAuthenticated) {
        await _tokenManager.storeSession(response.session!);
        emit(
          AuthAuthenticatedState(
            user: response.user!,
            session: response.session!,
          ),
        );
      } else {
        emit(AuthErrorState(message: response.message ?? 'Sign up failed'));
      }
    } catch (e) {
      emit(
        AuthErrorState(message: _getErrorMessage(e), code: _getErrorCode(e)),
      );
    }
  }

  Future<void> _onVerifySignUp(
    AuthVerifySignUpEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoadingState());

    try {
      final response = await _authRepository.verifySignUp(
        email: event.email,
        token: event.token,
        password: event.password,
      );

      if (response.isAuthenticated) {
        await _tokenManager.storeSession(response.session!);
        emit(
          AuthAuthenticatedState(
            user: response.user!,
            session: response.session!,
          ),
        );
      } else {
        emit(
          AuthErrorState(message: response.message ?? 'Verification failed'),
        );
      }
    } catch (e) {
      emit(
        AuthErrorState(message: _getErrorMessage(e), code: _getErrorCode(e)),
      );
    }
  }

  Future<void> _onSignInWithEmail(
    AuthSignInWithEmailEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoadingState());

    try {
      final response = await _authRepository.signInWithEmail(
        email: event.email,
      );

      if (response.isOtpSent) {
        emit(
          AuthOtpSentState(
            email: event.email,
            message: response.message ?? 'OTP sent to your email',
            type: 'signin',
          ),
        );
      } else if (response.isAuthenticated) {
        await _tokenManager.storeSession(response.session!);
        emit(
          AuthAuthenticatedState(
            user: response.user!,
            session: response.session!,
          ),
        );
      } else {
        emit(AuthErrorState(message: response.message ?? 'Sign in failed'));
      }
    } catch (e) {
      emit(
        AuthErrorState(message: _getErrorMessage(e), code: _getErrorCode(e)),
      );
    }
  }

  Future<void> _onVerifySignIn(
    AuthVerifySignInEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoadingState());

    try {
      final response = await _authRepository.verifySignIn(
        email: event.email,
        token: event.token,
      );

      if (response.isAuthenticated) {
        await _tokenManager.storeSession(response.session!);
        emit(
          AuthAuthenticatedState(
            user: response.user!,
            session: response.session!,
          ),
        );
      } else {
        emit(
          AuthErrorState(message: response.message ?? 'Verification failed'),
        );
      }
    } catch (e) {
      emit(
        AuthErrorState(message: _getErrorMessage(e), code: _getErrorCode(e)),
      );
    }
  }

  Future<void> _onSignUp(AuthSignUpEvent event, Emitter<AuthState> emit) async {
    emit(const AuthLoadingState());

    try {
      final response = await _authRepository.signUp(
        email: event.email,
        password: event.password,
        data: event.data,
      );

      if (response.isOtpSent) {
        emit(
          AuthOtpSentState(
            email: event.email,
            message: response.message ?? 'OTP sent to your email',
            type: 'signup',
          ),
        );
      } else if (response.isAuthenticated) {
        await _tokenManager.storeSession(response.session!);
        emit(
          AuthAuthenticatedState(
            user: response.user!,
            session: response.session!,
          ),
        );
      } else {
        emit(AuthErrorState(message: response.message ?? 'Sign up failed'));
      }
    } catch (e) {
      emit(
        AuthErrorState(message: _getErrorMessage(e), code: _getErrorCode(e)),
      );
    }
  }

  Future<void> _onSignInWithPassword(
    AuthSignInWithPasswordEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoadingState());

    try {
      final response = await _authRepository.signInWithPassword(
        email: event.email,
        password: event.password,
      );

      if (response.isAuthenticated) {
        await _tokenManager.storeSession(response.session!);
        emit(
          AuthAuthenticatedState(
            user: response.user!,
            session: response.session!,
          ),
        );
      } else if (response.isMfaRequired) {
        // Account has a verified second factor — withhold the session and
        // surface the challenge so the caller can complete it via verifyMfa.
        emit(
          AuthMfaRequiredState(
            challengeToken: response.challengeToken!,
            factors: response.mfaFactors,
          ),
        );
      } else {
        emit(AuthErrorState(message: response.message ?? 'Sign in failed'));
      }
    } catch (e) {
      emit(
        AuthErrorState(message: _getErrorMessage(e), code: _getErrorCode(e)),
      );
    }
  }

  Future<void> _onVerifyMfa(
    AuthVerifyMfaEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoadingState());

    try {
      final response = await _authRepository.verifyMfa(
        challengeToken: event.challengeToken,
        code: event.code,
      );

      if (response.isAuthenticated) {
        await _tokenManager.storeSession(response.session!);
        emit(
          AuthAuthenticatedState(
            user: response.user!,
            session: response.session!,
          ),
        );
      } else {
        emit(AuthErrorState(
            message: response.message ?? 'MFA verification failed'));
      }
    } catch (e) {
      emit(
        AuthErrorState(message: _getErrorMessage(e), code: _getErrorCode(e)),
      );
    }
  }

  Future<void> _onVerifySmsOtp(
    AuthVerifySmsOtpEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoadingState());

    try {
      final response = await _authRepository.verifySmsOtp(
        phone: event.phone,
        code: event.code,
      );

      if (response.isAuthenticated) {
        await _tokenManager.storeSession(response.session!);
        emit(
          AuthAuthenticatedState(
            user: response.user!,
            session: response.session!,
          ),
        );
      } else {
        emit(AuthErrorState(
            message: response.message ?? 'SMS verification failed'));
      }
    } catch (e) {
      emit(
        AuthErrorState(message: _getErrorMessage(e), code: _getErrorCode(e)),
      );
    }
  }

  Future<void> _onSignOut(
    AuthSignOutEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoadingState());

    // Bypass proactive token refresh for the duration of sign-out. Otherwise
    // the /auth/signout request's interceptor would trigger a refresh that
    // enqueues an event on this (single-threaded) bloc while it is still
    // awaiting signOut() — a deadlock that strands the UI on AuthLoadingState.
    _tokenManager.markSigningOut();

    try {
      await _authRepository.signOut();
      await _tokenManager.clearSession();
      emit(const AuthUnauthenticatedState());
    } catch (e) {
      // Even if sign out fails on server, clear local session
      await _tokenManager.clearSession();
      emit(const AuthUnauthenticatedState());
    }
  }

  Future<void> _onRefreshSession(
    AuthRefreshSessionEvent event,
    Emitter<AuthState> emit,
  ) async {
    // Bloc drops a state equal to the current one; without this an explicit
    // refresh that ends Unauthenticated while already Unauthenticated would
    // never notify the waiting caller.
    if (!event.silent) emit(const AuthLoadingState());
    try {
      final refreshToken =
          event.refreshToken ?? await _tokenManager.getRefreshToken();

      if (refreshToken == null) {
        emit(const AuthUnauthenticatedState());
        return;
      }

      // Route through the TokenManager's de-duplicated refresh rather than
      // calling the repository directly. The backend rotates refresh tokens
      // single-use: two parallel /auth/refresh calls with the same token make
      // one win (rotating + persisting a new token) and the other 401. If this
      // bloc refresh raced a concurrent interceptor/proactive refresh and lost,
      // the old code would `clearSession()` here — wiping the session the
      // *winning* refresh had just persisted, dropping the user to the sign-in
      // screen on the next cold start. Sharing the single in-flight request
      // (TokenManager._pendingRefresh) means both callers see the same result
      // and the race disappears. `_performTokenRefresh` stores the rotated
      // session, so on success we re-read it to emit.
      final refreshed = await _tokenManager.refreshSession();

      if (refreshed) {
        final session = await _tokenManager.getStoredSession();
        if (session != null) {
          emit(
            AuthAuthenticatedState(user: session.user, session: session),
          );
          return;
        }
      }

      if (_tokenManager.lastRefreshFailedTransiently) {
        // Offline / timeout / 5xx: the refresh token may still be valid, so
        // keep the stored session — the next request retries the refresh.
        if (!event.silent) {
          emit(const AuthErrorState(
            message: 'Could not refresh the session: network or server unavailable',
            code: 'REFRESH_FAILED',
          ));
        }
        return;
      }

      // The server rejected the refresh token: the session is really over.
      await _tokenManager.clearSession();
      emit(const AuthUnauthenticatedState());
    } catch (e) {
      // Unexpected local failure — never wipe the stored session for it.
      if (!event.silent) {
        emit(AuthErrorState(message: _getErrorMessage(e), code: _getErrorCode(e)));
      }
    }
  }

  Future<void> _onUpdateUser(
    AuthUpdateUserEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoadingState());

    try {
      final response = await _authRepository.updateUser(
        email: event.email,
        password: event.password,
        currentPassword: event.currentPassword,
        data: event.data,
      );

      // Persist updated user into stored session so it survives app restarts.
      // Without this, _onInitialize would restore the stale user (without
      // display_name) on next launch.
      Session? updatedSession;
      try {
        final currentSession = await _tokenManager.getStoredSession();
        if (currentSession != null) {
          updatedSession = currentSession.copyWith(user: response.user);
          await _tokenManager.storeSession(updatedSession);
        }
      } catch (sessionError) {
        // Non-fatal – user is updated in memory even if storage fails
      }

      emit(
        AuthUserUpdatedState(user: response.user, message: response.message),
      );

      // Re-emit AuthAuthenticatedState with the refreshed user so the
      // long-lived bloc state reflects the new profile. Without this,
      // consumers that filter for AuthAuthenticatedState (or rely on
      // OrbitNestAuth._lastKnownSession, which is only refreshed on
      // AuthAuthenticatedState) keep showing the stale user once any
      // subsequent transient state fires.
      if (updatedSession != null) {
        emit(
          AuthAuthenticatedState(
            user: response.user,
            session: updatedSession,
          ),
        );
      }
    } catch (e) {
      emit(
        AuthErrorState(message: _getErrorMessage(e), code: _getErrorCode(e)),
      );
    }
  }

  Future<void> _onGetUser(
    AuthGetUserEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoadingState()); // see _onRefreshSession
    try {
      final user = await _authRepository.getUser();
      final session = await _tokenManager.getStoredSession();

      if (user != null && session != null) {
        emit(AuthAuthenticatedState(user: user, session: session));
      } else {
        emit(const AuthUnauthenticatedState());
      }
    } catch (e) {
      emit(
        AuthErrorState(message: _getErrorMessage(e), code: _getErrorCode(e)),
      );
    }
  }

  Future<void> _onResetPasswordForEmail(
    AuthResetPasswordForEmailEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoadingState());

    try {
      final response = await _authRepository.resetPasswordForEmail(
        email: event.email,
      );

      emit(
        AuthPasswordResetSentState(
          email: event.email,
          message: response.message,
        ),
      );
    } catch (e) {
      emit(
        AuthErrorState(message: _getErrorMessage(e), code: _getErrorCode(e)),
      );
    }
  }

  Future<void> _onUpdatePassword(
    AuthUpdatePasswordEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoadingState());

    try {
      final response = await _authRepository.updatePassword(
        email: event.email,
        token: event.token,
        password: event.password,
      );

      // The API answers {success, message} with no user or session — the user
      // signs in again with the new password.
      emit(
        AuthPasswordResetSentState(
          email: event.email,
          message: response.message ?? 'Password has been reset',
        ),
      );
    } catch (e) {
      emit(
        AuthErrorState(message: _getErrorMessage(e), code: _getErrorCode(e)),
      );
    }
  }

  Future<void> _onInitialize(
    AuthInitializeEvent event,
    Emitter<AuthState> emit,
  ) async {
    try {
      final session = await _tokenManager.getStoredSession();

      if (session == null) {
        emit(const AuthUnauthenticatedState());
        return;
      }

      // Check if token needs refresh (expired or expiring within 5 minutes)
      final accessTokenExpired = _tokenManager.isTokenExpired(
        session.accessToken,
      );
      final accessTokenExpiringSoon = _tokenManager.needsRefresh(
        session.accessToken,
      );

      if (accessTokenExpired || accessTokenExpiringSoon) {
        // Emit the stored user immediately so currentUser is never null during
        // init. The AuthInterceptor handles 401→refresh→retry on any API call,
        // so callers are unblocked even though the token is stale.
        emit(AuthAuthenticatedState(user: session.user, session: session));
        add(AuthRefreshSessionEvent(
            refreshToken: session.refreshToken, silent: true));
        return;
      }

      emit(AuthAuthenticatedState(user: session.user, session: session));

      // Kick off a background fetch of the latest user profile so any stale
      // stored session (e.g. missing user_metadata set in a previous app run
      // right before a crash / force-quit) is reconciled with the server on
      // next launch. Fire-and-forget — the in-memory state is already emitted
      // above so the UI is unblocked.
      unawaited(_reconcileStoredUserFromServer(session));
    } catch (e) {
      emit(const AuthUnauthenticatedState());
    }
  }

  /// Fetch the authoritative user record from GET /auth/user and, if it
  /// differs from the one in the stored session, persist the fresher copy
  /// back to secure storage. This keeps `user_metadata` (display_name, etc.)
  /// from going stale across app restarts — the upper app layer
  /// (AppAuthBloc) is responsible for emitting the refreshed UI state via
  /// its own `refreshCurrentUser` pathway; here we only fix the persistence
  /// so that *subsequent* cold starts see the latest user.
  Future<void> _reconcileStoredUserFromServer(Session currentSession) async {
    try {
      final freshUser = await _authRepository.getUser();
      if (freshUser == null) return;

      // If the server copy already matches what we have in storage, skip
      // the extra write.
      final inMemoryMetadata = currentSession.user.userMetadata;
      final freshMetadata = freshUser.userMetadata;
      final metadataChanged =
          (inMemoryMetadata?.toString() ?? '') !=
          (freshMetadata?.toString() ?? '');
      if (!metadataChanged &&
          currentSession.user.email == freshUser.email &&
          currentSession.user.id == freshUser.id) {
        return;
      }

      // Re-read the LATEST stored session before writing. The getUser() call
      // above can trigger a token refresh (proactive, or 401→refresh in the
      // interceptor), which rotates and persists a NEW refresh token. Merging
      // the fresh user onto `currentSession` (captured *before* the call) and
      // storing that would overwrite the rotated token with the now-invalid
      // old one — silently breaking the next cold-start refresh. Merge onto
      // whatever tokens are current instead, and skip entirely if the session
      // was cleared meanwhile (e.g. a concurrent sign-out).
      final latest = await _tokenManager.getStoredSession();
      if (latest == null) return;
      final updatedSession = latest.copyWith(user: freshUser);
      await _tokenManager.storeSession(updatedSession);
    } catch (e) {
      // Background user reconciliation failed (non-fatal)
    }
  }

  Future<void> _onClearError(
    AuthClearErrorEvent event,
    Emitter<AuthState> emit,
  ) async {
    if (state is AuthErrorState) {
      emit(const AuthInitialState());
    }
  }

  // ── Passkey handlers ──────────────────────────────────────────────────────

  Future<void> _onRegisterPasskey(
    AuthRegisterPasskeyEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoadingState());
    try {
      final options = await _authRepository.passkeyRegisterOptions(
        deviceName: event.deviceName,
      );
      final attestation = await _passkeyAuthenticator.register(
        Map<String, dynamic>.from(options['publicKey'] as Map),
      );
      final saved = await _authRepository.passkeyRegisterVerify(
        challengeId: options['challenge_id'] as String,
        attestation: attestation,
        deviceName: event.deviceName,
      );
      emit(AuthPasskeyRegisteredState(device: PasskeyDevice.fromJson(saved)));
    } catch (e) {
      emit(AuthErrorState(message: _getErrorMessage(e), code: _getErrorCode(e)));
    }
  }

  Future<void> _onSignInWithPasskey(
    AuthSignInWithPasskeyEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoadingState());
    try {
      final options = await _authRepository.passkeyLoginOptions(
        identifier: event.identifier,
      );
      final assertion = await _passkeyAuthenticator.authenticate(
        Map<String, dynamic>.from(options['publicKey'] as Map),
      );
      final response = await _authRepository.passkeyLoginVerify(
        challengeId: options['challenge_id'] as String,
        assertion: assertion,
      );
      if (response.isAuthenticated) {
        await _tokenManager.storeSession(response.session!);
        emit(AuthAuthenticatedState(
          user: response.user!,
          session: response.session!,
        ));
      } else {
        emit(AuthErrorState(
          message: response.message ?? 'Passkey sign-in failed',
        ));
      }
    } catch (e) {
      emit(AuthErrorState(message: _getErrorMessage(e), code: _getErrorCode(e)));
    }
  }

  Future<void> _onSignUpWithPasskey(
    AuthSignUpWithPasskeyEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoadingState());
    try {
      final options = await _authRepository.passkeySignupOptions(
        email: event.email,
        userMetadata: event.userMetadata,
        deviceName: event.deviceName,
      );
      final attestation = await _passkeyAuthenticator.register(
        Map<String, dynamic>.from(options['publicKey'] as Map),
      );
      final response = await _authRepository.passkeySignupVerify(
        challengeId: options['challenge_id'] as String,
        attestation: attestation,
        deviceName: event.deviceName,
      );
      if (response.isAuthenticated) {
        await _tokenManager.storeSession(response.session!);
        emit(AuthAuthenticatedState(
          user: response.user!,
          session: response.session!,
        ));
      } else {
        emit(AuthErrorState(
          message: response.message ?? 'Passkey sign-up failed',
        ));
      }
    } catch (e) {
      emit(AuthErrorState(message: _getErrorMessage(e), code: _getErrorCode(e)));
    }
  }

  Future<void> _onListPasskeys(
    AuthListPasskeysEvent event,
    Emitter<AuthState> emit,
  ) async {
    try {
      final raw = await _authRepository.listPasskeys();
      final devices = raw.map((j) => PasskeyDevice.fromJson(j)).toList();
      emit(AuthPasskeysListedState(devices: devices));
    } catch (e) {
      emit(AuthErrorState(message: _getErrorMessage(e), code: _getErrorCode(e)));
    }
  }

  Future<void> _onRenamePasskey(
    AuthRenamePasskeyEvent event,
    Emitter<AuthState> emit,
  ) async {
    try {
      await _authRepository.renamePasskey(
        deviceId: event.deviceId,
        deviceName: event.deviceName,
      );
      emit(AuthPasskeyUpdatedState(
        deviceId: event.deviceId,
        message: 'Passkey renamed',
      ));
    } catch (e) {
      emit(AuthErrorState(message: _getErrorMessage(e), code: _getErrorCode(e)));
    }
  }

  Future<void> _onRevokePasskey(
    AuthRevokePasskeyEvent event,
    Emitter<AuthState> emit,
  ) async {
    try {
      await _authRepository.revokePasskey(deviceId: event.deviceId);
      emit(AuthPasskeyRevokedState(deviceId: event.deviceId));
    } catch (e) {
      emit(AuthErrorState(message: _getErrorMessage(e), code: _getErrorCode(e)));
    }
  }

  String _getErrorMessage(dynamic error) {
    if (error is AuthException) {
      return error.message;
    }
    return error.toString();
  }

  String? _getErrorCode(dynamic error) {
    if (error is AuthException) {
      return error.code;
    }
    return null;
  }
}
