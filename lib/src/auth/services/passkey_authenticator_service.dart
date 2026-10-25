import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

import '../exceptions/auth_exception.dart';
import '../../constants/error_codes.dart';

/// Bridges WebAuthn options/responses produced by the NestCore server with the
/// platform credential APIs (Android Credential Manager, iOS ASAuthorization).
///
/// Server returns a standard PublicKeyCredentialCreation/RequestOptionsJSON;
/// this wrapper feeds it to the `passkeys` plugin and returns the response in
/// the standard WebAuthn JSON format ready to POST back to the verify endpoint.
class PasskeyAuthenticatorService {
  PasskeyAuthenticatorService({PasskeyAuthenticator? authenticator})
      : _authenticator = authenticator ?? PasskeyAuthenticator();

  final PasskeyAuthenticator _authenticator;

  /// True if the platform exposes any passkey authenticator at all.
  Future<bool> isAvailable() async {
    try {
      // ignore: deprecated_member_use
      return await _authenticator.canAuthenticate();
    } catch (_) {
      return false;
    }
  }

  /// Drive a registration ceremony for the given server options.
  /// [options] is the raw `publicKey` map from `/auth/passkey/register/options`.
  /// Returns the attestation JSON that should be posted to `/register/verify`.
  Future<Map<String, dynamic>> register(Map<String, dynamic> options) async {
    final request = RegisterRequestType.fromJson(options);
    try {
      final response = await _authenticator.register(request);
      return response.toJson();
    } on PasskeyAuthCancelledException {
      throw const AuthException(
        'Passkey registration was cancelled.',
        code: ErrorCodes.passkeyCancelled,
      );
    } on ExcludeCredentialsCanNotBeRegisteredException {
      throw const AuthException(
        'A passkey is already registered for this device.',
        code: ErrorCodes.passkeyAlreadyExists,
      );
    } on DeviceNotSupportedException {
      throw const AuthException(
        'This device does not support passkeys.',
        code: ErrorCodes.passkeyUnsupported,
      );
    } on PasskeyUnsupportedException catch (e) {
      throw AuthException(
        e.message ?? 'Passkeys are not supported on this device.',
        code: ErrorCodes.passkeyUnsupported,
      );
    } on DomainNotAssociatedException catch (e) {
      throw AuthException(
        e.message ?? 'Relying-party domain is not associated with this app.',
        code: ErrorCodes.passkeyDomainNotAssociated,
      );
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }

  /// Drive an authentication ceremony for the given server options.
  /// [options] is the raw `publicKey` map from `/auth/passkey/login/options`.
  /// Returns the assertion JSON that should be posted to `/login/verify`.
  Future<Map<String, dynamic>> authenticate(Map<String, dynamic> options) async {
    final request = AuthenticateRequestType.fromJson(options);
    try {
      final response = await _authenticator.authenticate(request);
      return response.toJson();
    } on NoCredentialsAvailableException {
      throw const AuthException(
        'No passkey is available on this device.',
        code: ErrorCodes.passkeyNotAvailable,
      );
    } on PasskeyAuthCancelledException {
      throw const AuthException(
        'Passkey sign-in was cancelled.',
        code: ErrorCodes.passkeyCancelled,
      );
    } on DeviceNotSupportedException {
      throw const AuthException(
        'This device does not support passkeys.',
        code: ErrorCodes.passkeyUnsupported,
      );
    } on PasskeyUnsupportedException catch (e) {
      throw AuthException(
        e.message ?? 'Passkeys are not supported on this device.',
        code: ErrorCodes.passkeyUnsupported,
      );
    } on DomainNotAssociatedException catch (e) {
      throw AuthException(
        e.message ?? 'Relying-party domain is not associated with this app.',
        code: ErrorCodes.passkeyDomainNotAssociated,
      );
    } catch (e) {
      throw AuthException.fromException(e);
    }
  }
}
