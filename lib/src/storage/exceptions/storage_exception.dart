import 'dart:convert';

import 'package:dio/dio.dart';
import '../../client/interceptors/error_interceptor.dart';

/// Thrown by every [StorageBucket] request method.
///
/// [statusCode], [code], [message] and [body] come from the API error body,
/// e.g. `402 QUOTA_EXCEEDED` (with `quota`/`plan`/`limit`/`usage` in [body]),
/// `403` for a private bucket the caller can't read, `404` for a missing
/// bucket or file.
class StorageException extends OrbitNestException {
  const StorageException(
    super.message, {
    super.code,
    super.statusCode,
    super.body,
  });

  factory StorageException.fromException(Object error) {
    if (error is StorageException) return error;
    if (error is DioException) {
      final wrapped = error.error is OrbitNestException ? error.error as OrbitNestException : null;
      var body = wrapped?.body;
      // download() asks for bytes, so its error body arrives undecoded.
      final raw = error.response?.data;
      if (body == null && raw is List<int>) {
        try {
          final decoded = jsonDecode(utf8.decode(raw));
          if (decoded is Map<String, dynamic>) body = decoded;
        } catch (_) {}
      }
      final m = body?['message'] ?? body?['error'];
      return StorageException(
        m is List ? m.join(', ') : m?.toString() ?? wrapped?.message ?? error.message ?? 'Storage request failed',
        code: body?['code']?.toString() ?? wrapped?.code,
        statusCode: error.response?.statusCode ?? wrapped?.statusCode,
        body: body,
      );
    }
    if (error is OrbitNestException) {
      return StorageException(error.message, code: error.code, statusCode: error.statusCode, body: error.body);
    }
    return StorageException(error.toString(), code: 'UNKNOWN_STORAGE_ERROR');
  }

  @override
  String toString() => code != null ? 'StorageException($code): $message' : 'StorageException: $message';
}
