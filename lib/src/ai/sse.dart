// Internal: one server-sent-events POST over dart:io. Not exported.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../client/http_client.dart';

/// A failure before or during an SSE request; the stream ends after it.
class SseFailure {
  final String message;
  final String? code;
  final int? statusCode;
  const SseFailure(this.message, {this.code, this.statusCode});
}

/// POST [body] to [path] and yield each `data:` event as a JSON map, or one
/// [SseFailure] (never a thrown error). Cancelling the subscription destroys
/// the socket, which stops the work at the server.
///
/// dart:io, not Dio: cancelling a Dio stream drains the rest of the body (the
/// server keeps generating and billing). A per-stream client closed with
/// force destroys the socket.
Stream<Object> postSse(
  NestCoreHttpClient http,
  String path,
  Map<String, dynamic> body, {
  Duration headersTimeout = const Duration(seconds: 130),
}) async* {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  var closed = false;
  try {
    final HttpClientResponse res;
    try {
      final req = await client.postUrl(Uri.parse('${http.baseUrl}$path'));
      (await http.authHeaders()).forEach(req.headers.set);
      req.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'text/event-stream');
      req.followRedirects = false;
      req.add(utf8.encode(jsonEncode(body)));
      res = await req.close().timeout(headersTimeout);
    } catch (e) {
      yield SseFailure('Network error: $e', code: 'NETWORK_ERROR');
      return;
    }
    if (res.statusCode != 200) {
      Map<String, dynamic>? err;
      try {
        err = Map<String, dynamic>.from(jsonDecode(await utf8.decodeStream(res)) as Map);
      } catch (_) {}
      final m = err?['message'] ?? err?['error'];
      yield SseFailure(m is List ? m.join(', ') : m?.toString() ?? 'Request failed (${res.statusCode})',
          code: err?['code']?.toString(), statusCode: res.statusCode);
      return;
    }
    try {
      await for (final line in res.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        yield Map<String, dynamic>.from(jsonDecode(line.substring(5).trim()) as Map);
      }
    } catch (e) {
      if (!closed) yield SseFailure('Stream interrupted: $e', code: 'STREAM_ERROR');
    }
  } finally {
    // Also runs when the listener cancels.
    closed = true;
    client.close(force: true);
  }
}
