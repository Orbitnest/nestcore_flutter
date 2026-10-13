import 'dart:async';
import 'package:uuid/uuid.dart';
import '../../client/http_client.dart';
import '../models/analytics_event.dart';

const int _kBatchSize = 50;
const Duration _kFlushDelay = Duration(seconds: 5);

class AnalyticsService {
  final OrbitNestHttpClient _httpClient;
  final String _baseUrl;

  final String anonymousId;
  final String sessionId;

  String? _userId;
  final List<AnalyticsEvent> _queue = [];
  Timer? _flushTimer;

  AnalyticsService({
    required OrbitNestHttpClient httpClient,
    required String baseUrl,
  })  : _httpClient = httpClient,
        _baseUrl = baseUrl,
        anonymousId = const Uuid().v4(),
        sessionId = const Uuid().v4();

  void identify(String userId, {Map<String, dynamic>? traits}) {
    _userId = userId;
    _enqueue('identify', properties: traits);
  }

  void track(String event, {Map<String, dynamic>? properties}) {
    _enqueue(event, properties: properties);
  }

  void screen(String screenName, {Map<String, dynamic>? properties}) {
    _enqueue('screen_view', properties: {
      'screen': screenName,
      ...?properties,
    });
  }

  void crash(Object error, {StackTrace? stackTrace, Map<String, dynamic>? properties}) {
    // Field names the server's crash grouping reads.
    _enqueue('crash', properties: {
      'error_type': error.runtimeType.toString(),
      'error_message': error.toString(),
      if (stackTrace != null) 'stack_trace': stackTrace.toString(),
      ...?properties,
    });
  }

  void _enqueue(String event, {Map<String, dynamic>? properties}) {
    final analyticsEvent = AnalyticsEvent(
      eventId: const Uuid().v4(),
      event: event,
      anonymousId: anonymousId,
      platform: 'flutter',
      timestamp: DateTime.now().toUtc().toIso8601String(),
      sessionId: sessionId,
      userId: _userId,
      properties: properties,
    );

    _queue.add(analyticsEvent);

    if (_queue.length >= _kBatchSize) {
      unawaited(flush());
      return;
    }

    _flushTimer ??= Timer(_kFlushDelay, () {
      unawaited(flush());
    });
  }

  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;

    if (_queue.isEmpty) return;

    final batch = List<AnalyticsEvent>.from(_queue);
    _queue.clear();

    try {
      await _httpClient.post(
        '$_baseUrl/api/analytics/events',
        data: {'events': batch.map((e) => e.toJson()).toList()},
      );
    } catch (_) {
      // Silently discard failed batches — analytics must never crash the app.
    }
  }

  /// Sends any queued events, then stops the flush timer.
  Future<void> dispose() => flush();
}
