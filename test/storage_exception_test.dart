import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nestcore_flutter/nestcore_flutter.dart';
import 'package:nestcore_flutter/src/client/http_client.dart';

/// Throws what Dio + ErrorInterceptor produce for an API error response.
class _FailingHttpClient implements NestCoreHttpClient {
  _FailingHttpClient(this.status, this.body, {this.asBytes = false});
  final int status;
  final Map<String, dynamic> body;
  final bool asBytes;

  Never _fail(String path) {
    final req = RequestOptions(path: path);
    throw DioException(
      requestOptions: req,
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: req,
        statusCode: status,
        data: asBytes ? utf8.encode(jsonEncode(body)) : body,
      ),
      error: asBytes
          ? NestCoreException('Not Found', code: 'NOT_FOUND', statusCode: status)
          : NestCoreException(body['message'] as String, code: body['code'] as String?, statusCode: status, body: body),
    );
  }

  @override
  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters, Options? options, CancelToken? cancelToken, ProgressCallback? onReceiveProgress}) async => _fail(path);

  @override
  Future<Response<T>> post<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters, Options? options, CancelToken? cancelToken, ProgressCallback? onSendProgress, ProgressCallback? onReceiveProgress}) async => _fail(path);

  @override
  Future<Response<T>> delete<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters, Options? options, CancelToken? cancelToken}) async => _fail(path);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

StorageBucket _bucket(_FailingHttpClient http) =>
    NestCoreStorage(httpClient: http, baseUrl: 'https://api.test', projectSlug: 'p').from('avatars');

void main() {
  test('upload over quota throws StorageException with the API code and body', () async {
    final bucket = _bucket(_FailingHttpClient(402, {
      'statusCode': 402,
      'code': 'QUOTA_EXCEEDED',
      'message': 'Storage quota exceeded',
      'quota': 'storage',
      'limit': 1024,
    }));
    try {
      await bucket.upload(path: 'a.png', bytes: Uint8List(1));
      fail('expected a StorageException');
    } on StorageException catch (e) {
      expect(e.statusCode, 402);
      expect(e.code, 'QUOTA_EXCEEDED');
      expect(e.message, 'Storage quota exceeded');
      expect(e.body?['limit'], 1024);
      expect(e, isA<NestCoreException>());
    }
  });

  test('list / remove / createBucket throw StorageException', () async {
    final bucket = _bucket(_FailingHttpClient(403, {'statusCode': 403, 'message': 'Private bucket'}));
    await expectLater(bucket.list(), throwsA(isA<StorageException>().having((e) => e.statusCode, 'statusCode', 403)));
    await expectLater(bucket.remove(['a']), throwsA(isA<StorageException>()));
    await expectLater(bucket.createBucket(), throwsA(isA<StorageException>()));
  });

  test('download decodes the byte error body', () async {
    final bucket = _bucket(_FailingHttpClient(404, {'statusCode': 404, 'message': 'Bucket not found: avatars'}, asBytes: true));
    await expectLater(
      bucket.download('a.png'),
      throwsA(isA<StorageException>()
          .having((e) => e.statusCode, 'statusCode', 404)
          .having((e) => e.message, 'message', 'Bucket not found: avatars')
          .having((e) => e.code, 'code', 'NOT_FOUND')),
    );
  });
}
