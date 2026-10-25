import 'services/analytics_service.dart';

class NestCoreAnalytics {
  final AnalyticsService _service;

  NestCoreAnalytics(AnalyticsService service) : _service = service;

  void identify(String userId, {Map<String, dynamic>? traits}) =>
      _service.identify(userId, traits: traits);

  void track(String event, {Map<String, dynamic>? properties}) =>
      _service.track(event, properties: properties);

  void screen(String screenName, {Map<String, dynamic>? properties}) =>
      _service.screen(screenName, properties: properties);

  void crash(Object error, {StackTrace? stackTrace, Map<String, dynamic>? properties}) =>
      _service.crash(error, stackTrace: stackTrace, properties: properties);

  Future<void> flush() => _service.flush();
}
