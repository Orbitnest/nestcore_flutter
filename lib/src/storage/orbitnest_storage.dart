import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../client/http_client.dart';
import 'exceptions/storage_exception.dart';

/// On-the-fly image transform options for [StorageBucket.getPublicUrl].
class StorageTransform {
  final int? width;
  final int? height;

  /// Output format: `webp`, `jpeg`, `png`, or `avif`.
  final String? format;

  /// Quality 1–100.
  final int? quality;

  /// Resize behaviour: `cover`, `contain`, `fill`, `inside`, or `outside`.
  final String? fit;

  const StorageTransform({this.width, this.height, this.format, this.quality, this.fit});

  Map<String, String> toQuery() {
    final q = <String, String>{};
    if (width != null) q['width'] = '$width';
    if (height != null) q['height'] = '$height';
    if (format != null) q['format'] = format!;
    if (quality != null) q['quality'] = '$quality';
    if (fit != null) q['fit'] = fit!;
    return q;
  }
}

/// Storage facade — `client.storage.from('bucket')` returns a [StorageBucket].
class OrbitNestStorage {
  final OrbitNestHttpClient _httpClient;
  final String _baseUrl;
  final String _projectSlug;

  OrbitNestStorage({
    required OrbitNestHttpClient httpClient,
    required String baseUrl,
    required String projectSlug,
  })  : _httpClient = httpClient,
        _baseUrl = baseUrl,
        _projectSlug = projectSlug;

  StorageBucket from(String bucket) =>
      StorageBucket(httpClient: _httpClient, baseUrl: _baseUrl, projectSlug: _projectSlug, bucket: bucket);
}

/// Operations scoped to a single storage bucket.
class StorageBucket {
  final OrbitNestHttpClient _httpClient;
  final String _baseUrl;
  final String _projectSlug;
  final String _bucket;

  StorageBucket({
    required OrbitNestHttpClient httpClient,
    required String baseUrl,
    required String projectSlug,
    required String bucket,
  })  : _httpClient = httpClient,
        _baseUrl = baseUrl,
        _projectSlug = projectSlug,
        _bucket = bucket;

  String get _basePath => '/api/project/$_projectSlug/storage/$_bucket';

  /// Every request failure surfaces as a [StorageException].
  static Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } catch (e) {
      throw StorageException.fromException(e);
    }
  }

  static String _encodePath(String path) =>
      path.split('/').where((s) => s.isNotEmpty).map(Uri.encodeComponent).join('/');

  /// Upload bytes to `path` within the bucket. Set [upsert] to overwrite.
  Future<Map<String, dynamic>> upload({
    required String path,
    required Uint8List bytes,
    String? contentType,
    bool upsert = false,
  }) => _guard(() async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: path.split('/').last,
        contentType: contentType != null ? DioMediaType.parse(contentType) : null,
      ),
      'path': path,
      if (upsert) 'upsert': 'true',
    });
    final res = await _httpClient.post('$_basePath/upload', data: form);
    final data = res.data;
    if (data is Map && data['data'] != null) return Map<String, dynamic>.from(data['data'] as Map);
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  });

  /// Download a file's raw bytes.
  Future<Uint8List> download(String path) => _guard(() async {
    final res = await _httpClient.get(
      '$_basePath/download/${_encodePath(path)}',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(List<int>.from(res.data as List));
  });

  /// List files in the bucket (optionally under [prefix]).
  Future<List<dynamic>> list({String? prefix}) => _guard(() async {
    final res = await _httpClient.get(
      _basePath,
      queryParameters: {if (prefix != null && prefix.isNotEmpty) 'prefix': prefix},
    );
    final data = res.data;
    if (data is List) return List<dynamic>.from(data);
    if (data is Map && data['data'] is List) return List<dynamic>.from(data['data'] as List);
    return const <dynamic>[];
  });

  /// Delete one or more files by path. Returns `{ deleted: [...], errors: [...] }`.
  Future<Map<String, dynamic>> remove(List<String> paths) => _guard(() async {
    final res = await _httpClient.delete(_basePath, data: {'paths': paths});
    final data = res.data;
    if (data is Map && data['data'] != null) return Map<String, dynamic>.from(data['data'] as Map);
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  });

  /// Build a public URL for a file. Pass [transform] for an on-the-fly image
  /// rendition (resize / format / quality). Access is governed by the bucket's
  /// public/RLS policy — this just builds the URL, it doesn't fetch.
  String getPublicUrl(String path, {StorageTransform? transform}) {
    var url = '$_baseUrl/api/public/$_projectSlug/storage/$_bucket/${_encodePath(path)}';
    final q = transform?.toQuery() ?? const {};
    if (q.isNotEmpty) {
      url += '?${q.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    }
    return url;
  }

  /// Create this bucket if it doesn't already exist.
  Future<Map<String, dynamic>> createBucket() => _guard(() async {
    final res = await _httpClient.post('$_basePath/create');
    return res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
  });
}
