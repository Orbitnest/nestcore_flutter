import 'realtime_channel.dart';

export 'realtime_events.dart';
export 'realtime_channel.dart'
    show RealtimeChannel, RealtimeFilter, ChannelStatus;

/// Supabase-style realtime facade exposed on [OrbitNestClient].
///
/// ```dart
/// final ch = client.realtime.channel('orders')
///   ..onPostgresChanges(
///       event: PgEvent.insert,
///       table: 'orders',
///       callback: (e) => print(e.newRow))
///   ..subscribe();
/// ```
class OrbitNestRealtime {
  final RealtimeChannelManager _manager;

  OrbitNestRealtime({
    required String baseUrl,
    required String projectSlug,
    required String apiKey,
    String? userJwt,
    Future<String?> Function()? accessTokenProvider,
    Future<void> Function()? onAuthRejected,
  }) : _manager = RealtimeChannelManager(
          // Keep only the project slug in the URL. The apikey is passed via the
          // WebSocket subprotocol (see RealtimeChannelManager) instead of the
          // query string so it is not written to proxy / gateway access logs.
          wsUrl: '${baseUrl.replaceFirst(RegExp(r'^http'), 'ws')}'
              '/realtime/v1/ws?project=$projectSlug',
          apiKey: apiKey,
          userJwt: userJwt,
          accessTokenProvider: accessTokenProvider,
          onAuthRejected: onAuthRejected,
        );

  /// Create or retrieve a named channel.
  ///
  /// Chain [RealtimeChannel.onPostgresChanges] / [RealtimeChannel.onBroadcast]
  /// calls, then call [RealtimeChannel.subscribe] to connect.
  RealtimeChannel channel(String name) => RealtimeChannel(name, _manager);

  /// Re-open the WebSocket (when channels are subscribed) so it picks up the
  /// current user token. Called automatically on sign-in / sign-out.
  Future<void> reconnect() => _manager.reconnect();

  /// Release all resources (closes the WebSocket).
  Future<void> dispose() => _manager.dispose();
}
