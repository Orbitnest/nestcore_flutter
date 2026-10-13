import 'package:dio/dio.dart';
import '../../client/http_client.dart';
import '../../constants/endpoints.dart';
import '../../constants/error_codes.dart';
import '../models/auth_response.dart';
import '../models/user.dart';
import '../exceptions/auth_exception.dart';

/// Service for handling authentication API calls
class AuthService {
  final OrbitNestHttpClient _httpClient;
  final String _projectSlug;

  AuthService({
    required OrbitNestHttpClient httpClient,
    required String projectSlug,
  })  : _httpClient = httpClient,
        _projectSlug = projectSlug;

  /// Sign up with email (OTP-based)
  Future<AuthResponse> signUpWithEmail({
    required String email,
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectSignupWithEmail(_projectSlug),
        data: {
          'email': email,
          if (data != null) 'user_metadata': data,
        },
      );

      return AuthResponse.fromJson(response.data);
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
      final response = await _httpClient.post(
        Endpoints.projectVerifySignup(_projectSlug),
        data: {
          'email': email,
          'code': token,
          if (password != null) 'password': password,
        },
      );

      try {
        return AuthResponse.fromJson(response.data);
      } catch (e) {
        // If parsing fails, provide detailed error information
        throw AuthException(
          'Failed to parse authentication response: ${e.toString()}',
          code: ErrorCodes.responseParseError,
        );
      }
    } catch (e) {
      if (e is AuthException) {
        rethrow; // Re-throw our custom parsing error
      }
      throw AuthException.fromException(e);
    }
  }

  /// Sign in with email (OTP-based)
  Future<AuthResponse> signInWithEmail({
    required String email,
  }) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectSigninWithEmail(_projectSlug),
        data: {
          'email': email,
        },
      );

      return AuthResponse.fromJson(response.data);
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
      final response = await _httpClient.post(
        Endpoints.projectVerifySignin(_projectSlug),
        data: {
          'email': email,
          'code': token,
        },
      );

      try {
        return AuthResponse.fromJson(response.data);
      } catch (e) {
        // If parsing fails, provide detailed error information
        throw AuthException(
          'Failed to parse authentication response: ${e.toString()}',
          code: ErrorCodes.responseParseError,
        );
      }
    } catch (e) {
      if (e is AuthException) {
        rethrow; // Re-throw our custom parsing error
      }
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
      final response = await _httpClient.post(
        Endpoints.projectSignup(_projectSlug),
        data: {
          'email': email,
          'password': password,
          if (data != null) 'user_metadata': data,
        },
      );

      return AuthResponse.fromJson(response.data);
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
      final response = await _httpClient.post(
        Endpoints.projectSignin(_projectSlug),
        data: {
          'email': email,
          'password': password,
        },
      );

      return AuthResponse.fromJson(response.data);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Sign out the current user.
  ///
  /// Server-side session invalidation is best-effort: it is capped at a short
  /// timeout so logout stays responsive on slow/unstable networks. The caller
  /// clears the local session regardless of the outcome, so the user is logged
  /// out even if this request times out or fails — swallowing the error here
  /// keeps that the responsibility of the caller without surfacing a failure
  /// for an operation that does not block logout.
  Future<void> signOut() async {
    try {
      await _httpClient
          .post(Endpoints.projectSignout(_projectSlug))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Ignore — local session will be cleared by the caller regardless.
    }
  }

  /// Refresh the current session
  Future<AuthResponse> refreshSession({
    required String refreshToken,
  }) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectRefresh(_projectSlug),
        data: {
          'refresh_token': refreshToken,
        },
      );

      return AuthResponse.fromJson(response.data);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Get current user
  ///
  /// The server wraps the payload under a `user` key
  /// (`{"user": {"id": "...", "user_metadata": {...}}}`) so we unwrap it
  /// before constructing the model. If we passed `response.data` directly,
  /// `User.fromJson` would read `json['id']`/`json['user_metadata']` from the
  /// outer map and get `null` for every field — which silently corrupts the
  /// persisted user on cold start (`_reconcileStoredUserFromServer` in
  /// `AuthBloc._onInitialize` writes the result back to storage) and was the
  /// source of the "Not Set" full-name bug that resurfaced after the
  /// 8c010a8 reconcile was added.
  ///
  /// We also accept a non-wrapped payload defensively — the server contract
  /// has been inconsistent in the past and UserUpdateResponse.fromJson
  /// handles both shapes.
  Future<User> getUser() async {
    try {
      final response = await _httpClient.get(
        Endpoints.projectUser(_projectSlug),
      );

      final data = response.data as Map<String, dynamic>;
      final userJson = data.containsKey('user') && data['user'] is Map
          ? Map<String, dynamic>.from(data['user'] as Map)
          : data;
      return User.fromJson(userJson);
    } catch (e) {
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
      final response = await _httpClient.put(
        Endpoints.projectUser(_projectSlug),
        data: {
          if (email != null) 'email': email,
          if (password != null) 'password': password,
          if (currentPassword != null) 'current_password': currentPassword,
          if (data != null) 'data': data,
        },
      );

      return UserUpdateResponse.fromJson(response.data);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Permanently delete the signed-in user's account.
  Future<void> deleteUser() async {
    try {
      await _httpClient.delete(Endpoints.projectUser(_projectSlug));
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Confirm a pending email change with the code sent to the new address.
  Future<Map<String, dynamic>> verifyEmailChange(String code) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectVerifyEmailChange(_projectSlug),
        data: {'code': code},
      );
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Request password reset
  Future<PasswordResetResponse> resetPasswordForEmail({
    required String email,
  }) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectRecover(_projectSlug),
        data: {
          'email': email,
        },
      );

      return PasswordResetResponse.fromJson(response.data);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Update password with reset token.
  ///
  /// API expects `{ email, code, new_password }`. `token` is the 4-digit OTP
  /// from the recovery email — named `token` on the SDK surface for symmetry
  /// with other auth providers.
  Future<AuthResponse> updatePassword({
    required String email,
    required String token,
    required String password,
  }) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectResetPassword(_projectSlug),
        data: {
          'email': email,
          'code': token,
          'new_password': password,
        },
      );

      return AuthResponse.fromJson(response.data);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  // ── Passkey / WebAuthn ────────────────────────────────────────────────────

  /// Request server-issued attestation options for registering a new passkey.
  /// User must already be authenticated.
  Future<Map<String, dynamic>> passkeyRegisterOptions({String? deviceName}) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectPasskeyRegisterOptions(_projectSlug),
        data: {if (deviceName != null) 'device_name': deviceName},
      );
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Verify the platform attestation and persist the credential.
  Future<Map<String, dynamic>> passkeyRegisterVerify({
    required String challengeId,
    required Map<String, dynamic> attestation,
    String? deviceName,
  }) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectPasskeyRegisterVerify(_projectSlug),
        data: {
          'challenge_id': challengeId,
          'attestation': attestation,
          if (deviceName != null) 'device_name': deviceName,
        },
      );
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Begin a passkey sign-up ceremony — creates a passwordless user record
  /// on the server and returns WebAuthn attestation options.
  Future<Map<String, dynamic>> passkeySignupOptions({
    required String email,
    Map<String, dynamic>? userMetadata,
    String? deviceName,
  }) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectPasskeySignupOptions(_projectSlug),
        data: {
          'email': email,
          if (userMetadata != null) 'user_metadata': userMetadata,
          if (deviceName != null) 'device_name': deviceName,
        },
      );
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Finish a passkey sign-up ceremony. Returns an AuthResponse with the
  /// new session so the caller can store it.
  Future<AuthResponse> passkeySignupVerify({
    required String challengeId,
    required Map<String, dynamic> attestation,
    String? deviceName,
  }) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectPasskeySignupVerify(_projectSlug),
        data: {
          'challenge_id': challengeId,
          'attestation': attestation,
          if (deviceName != null) 'device_name': deviceName,
        },
      );
      return AuthResponse.fromJson(response.data);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Request server-issued assertion options for passkey sign-in.
  /// [identifier] may be the user email (enables `allowCredentials`) or null
  /// for a discoverable-credential flow.
  Future<Map<String, dynamic>> passkeyLoginOptions({String? identifier}) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectPasskeyLoginOptions(_projectSlug),
        data: {if (identifier != null) 'identifier': identifier},
      );
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Verify the platform assertion and exchange it for a session.
  Future<AuthResponse> passkeyLoginVerify({
    required String challengeId,
    required Map<String, dynamic> assertion,
  }) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectPasskeyLoginVerify(_projectSlug),
        data: {
          'challenge_id': challengeId,
          'assertion': assertion,
        },
      );
      return AuthResponse.fromJson(response.data);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// List all active passkeys for the current user.
  Future<List<Map<String, dynamic>>> listPasskeys() async {
    try {
      final response = await _httpClient.get(
        Endpoints.projectPasskeyDevices(_projectSlug),
      );
      return (response.data as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Rename a registered passkey.
  Future<Map<String, dynamic>> renamePasskey({
    required String deviceId,
    required String deviceName,
  }) async {
    try {
      final response = await _httpClient.patch(
        Endpoints.projectPasskeyDevice(_projectSlug, deviceId),
        data: {'device_name': deviceName},
      );
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Revoke (soft-delete) a registered passkey.
  Future<void> revokePasskey({required String deviceId}) async {
    try {
      await _httpClient.delete(
        Endpoints.projectPasskeyDevice(_projectSlug, deviceId),
      );
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Verify a JWT token against the server
  /// Returns a map with valid, user, and error fields
  Future<Map<String, dynamic>> verifyToken(String token) async {
    try {
      final response = await _httpClient.get(
        Endpoints.projectVerifyToken(_projectSlug),
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  // ─── SMS OTP (phone sign-in via the project's own Twilio) ───

  /// Send a one-time code to a phone number (E.164, e.g. `+15555550123`).
  Future<Map<String, dynamic>> signInWithSms({required String phone}) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectSmsSendOtp(_projectSlug),
        data: {'phone': phone},
      );
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Verify a phone OTP and sign in (creates the user on first sign-in).
  Future<AuthResponse> verifySmsOtp({
    required String phone,
    required String code,
  }) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectSmsVerifyOtp(_projectSlug),
        data: {'phone': phone, 'code': code},
      );
      return AuthResponse.fromJson(response.data);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  // ─── MFA (TOTP / authenticator apps) ───

  /// Begin TOTP enrollment — returns `secret`, `otpauth_url`, `qr_code`, `factor_id`.
  Future<Map<String, dynamic>> enrollMfaTotp({String? friendlyName, String? code}) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectMfaEnroll(_projectSlug),
        data: {
          if (friendlyName != null) 'friendly_name': friendlyName,
          if (code != null) 'code': code,
        },
      );
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Confirm a TOTP enrollment with the first code from the authenticator.
  Future<Map<String, dynamic>> verifyMfaEnrollment({
    required String factorId,
    required String code,
  }) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectMfaVerifyEnroll(_projectSlug),
        data: {'factor_id': factorId, 'code': code},
      );
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Regenerate the user's MFA recovery codes. Returns `{ codes: [...] }` once.
  Future<Map<String, dynamic>> regenerateMfaRecoveryCodes({String? code}) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectMfaRecoveryCodes(_projectSlug),
        data: {if (code != null) 'code': code},
      );
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// List the current user's MFA factors.
  Future<List<dynamic>> listMfaFactors() async {
    try {
      final response = await _httpClient.get(
        Endpoints.projectMfaFactors(_projectSlug),
      );
      return List<dynamic>.from(response.data as List);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Remove an MFA factor.
  Future<void> unenrollMfa({required String factorId, String? code}) async {
    try {
      await _httpClient.delete(
        Endpoints.projectMfaFactor(_projectSlug, factorId),
        data: {if (code != null) 'code': code},
      );
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Complete an MFA-gated sign-in with the challenge token and a TOTP code.
  Future<AuthResponse> verifyMfa({
    required String challengeToken,
    required String code,
  }) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectVerifyMfa(_projectSlug),
        data: {'challenge_token': challengeToken, 'code': code},
      );
      return AuthResponse.fromJson(response.data);
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }
}
