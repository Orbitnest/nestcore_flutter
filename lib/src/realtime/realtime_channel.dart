import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'realtime_events.dart';

// Filter operators for Postgres subscriptions.
class RealtimeFilter {
  final String column;
  final String op; // eq, neq, in, gt, lt, like
  final dynamic value;

  const RealtimeFilter({
    required this.column,
    required this.op,
    required this.value,
  });

  Map<String, dynamic> toJson() => {
        column: {op: value},
      };
}

// Internal handler registration.
class _Handler {
  final String type; // 'postgres_changes' | 'broadcast'
  final PgEvent? pgEvent;
  final String? table;
  final String? schema;
  final String? broadcastEvent;
  final RealtimeFilter? filter;
  final Function callback;

  const _Handler({
    required this.type,
    this.pgEvent,
    this.table,
    this.schema,
    this.broadcastEvent,
    this.filter,
    required this.callback,
  });
}

enum ChannelStatus { idle, connecting, connected, disconnected, error }

/// A realtime channel that aggregates DB-change and broadcast subscriptions.
///
/// Usage:
/// ```dart
/// final ch = client.channel('orders')
///   ..onPostgresChanges(
///       event: PgEvent.insert,
///       table: 'orders',
///       callback: (e) => print(e.newRow))
///   ..subscribe();
///
/// // Listen to the stream directly
/// ch.events.listen((e) { ... });
/// ```
class RealtimeChannel {
  final String name;
  final RealtimeChannelManager _manager;

  final List<_Handler> _handlers = [];
  final StreamController<RealtimeEvent> _eventController =
      StreamController<RealtimeEvent>.broadcast();

  ChannelStatus _status = ChannelStatus.idle;
  ChannelStatus get status => _status;

  // ─── Presence state ──────────────────────────────────────────────────────────
  final Map<String, List<dynamic>> _presenceState = {};
  final List<void Function(Map<String, List<dynamic>>)> _presenceSyncCallbacks = [];
  final List<void Function(String key, List<dynamic> presences)> _presenceJoinCallbacks = [];
  final List<void Function(String key, List<dynamic> presences)> _presenceLeaveCallbacks = [];

  RealtimeChannel(this.name, this._manager);

  /// Stream of all events on this channel.
  Stream<RealtimeEvent> get events => _eventController.stream;

  // ─── Handler registration ────────────────────────────────────────────────────

  RealtimeChannel onPostgresChanges({
    required PgEvent event,
    required String table,
    String schema = 'public',
    RealtimeFilter? filter,
    required void Function(PgChangesPayload) callback,
  }) {
    _handlers.add(_Handler(
      type: 'postgres_changes',
      pgEvent: event,
      table: table,
      schema: schema,
      filter: filter,
      callback: callback,
    ));
    return this;
  }

  RealtimeChannel onBroadcast({
    required String event,
    required void Function(BroadcastPayload) callback,
  }) {
    _handlers.add(_Handler(
      type: 'broadcast',
      broadcastEvent: event,
      callback: callback,
    ));
    return this;
  }

  // ─── Presence ────────────────────────────────────────────────────────────────

  /// Called whenever the server sends a full presence roster snapshot.
  RealtimeChannel onPresenceSync(
      void Function(Map<String, List<dynamic>> state) callback) {
    _presenceSyncCallbacks.add(callback);
    return this;
  }

  /// Called when a new socket appears in the presence roster.
  RealtimeChannel onPresenceJoin(
      void Function(String key, List<dynamic> presences) callback) {
    _presenceJoinCallbacks.add(callback);
    return this;
  }

  /// Called when a socket disappears from the presence roster.
  RealtimeChannel onPresenceLeave(
      void Function(String key, List<dynamic> presences) callback) {
    _presenceLeaveCallbacks.add(callback);
    return this;
  }

  /// Returns a read-only copy of the last-known presence roster.
  Map<String, List<dynamic>> getPresenceState() =>
      Map.unmodifiable(_presenceState);

  /// Track presence with the given [state] on this channel.
  /// Other subscribers will receive a `presence.state` update.
  Future<void> track(Map<String, dynamic> state) =>
      _manager._trackPresence(name, state);

  /// Stop tracking presence on this channel.
  Future<void> untrack() => _manager._untrackPresence(name);

  // ─── Subscribe / unsubscribe ─────────────────────────────────────────────────

  Future<void> subscribe() async {
    _status = ChannelStatus.connecting;
    await _manager._subscribe(this);
  }

  Future<void> unsubscribe() async {
    await _manager._unsubscribe(this);
    _status = ChannelStatus.disconnected;
  }

  // ─── Broadcast ───────────────────────────────────────────────────────────────

  Future<void> send({required String event, required dynamic payload}) async {
    await _manager._sendBroadcast(name, event, payload);
  }

  // ─── Internal ────────────────────────────────────────────────────────────────

  /// Message id that lets server `error` frames be routed back to this channel.
  String _msgId(String kind) =>
      '$name#${kind}_${DateTime.now().microsecondsSinceEpoch}';

  /// Server-side channel strings this channel subscribes to.
  Set<String> get _serverChannels => {
        for (final h in _handlers)
          if (h.type == 'postgres_changes')
            'table:${h.schema ?? 'public'}.${h.table}',
        if (_handlers.any((h) => h.type == 'broadcast') ||
            _presenceSyncCallbacks.isNotEmpty ||
            _presenceJoinCallbacks.isNotEmpty ||
            _presenceLeaveCallbacks.isNotEmpty)
          'broadcast:$name',
      };

  void _activate() {
    _status = ChannelStatus.connected;
    for (final h in _handlers) {
      if (h.type != 'postgres_changes') continue;
      final schema = h.schema ?? 'public';
      _manager._send({
        'id': _msgId('sub'),
        'type': 'subscribe',
        'channel': 'table:$schema.${h.table}',
        'events': _pgEventsToStrings(h.pgEvent ?? PgEvent.all),
        if (h.filter != null) 'filter': h.filter!.toJson(),
      });
    }
    if (_serverChannels.contains('broadcast:$name')) {
      _manager._send({
        'id': _msgId('sub'),
        'type': 'subscribe',
        'channel': 'broadcast:$name',
      });
    }
  }

  void _dispatch(Map<String, dynamic> msg) {
    if (msg['type'] == 'db_event') {
      final payload = PgChangesPayload.fromJson(msg);
      var matched = false;
      for (final h in _handlers) {
        if (h.type != 'postgres_changes') continue;
        final ops = _pgEventsToStrings(h.pgEvent ?? PgEvent.all);
        if (!ops.contains(msg['op']) && !ops.contains('*')) continue;
        if (h.table != null && h.table != msg['table']) continue;
        if (h.schema != null && h.schema != msg['schema']) continue;
        matched = true;
        (h.callback as void Function(PgChangesPayload))(payload);
      }
      // Only events for this channel's own tables reach [events].
      if (matched) _eventController.add(RealtimeDbEvent(payload));
    } else if (msg['type'] == 'broadcast') {
      final payload = BroadcastPayload.fromJson(msg);
      _eventController.add(RealtimeBroadcastEvent(payload));

      for (final h in _handlers) {
        if (h.type != 'broadcast') continue;
        if (h.broadcastEvent != '*' && h.broadcastEvent != msg['event']) continue;
        (h.callback as void Function(BroadcastPayload))(payload);
      }
    } else if (msg['type'] == 'presence.state') {
      final raw = msg['presences'] as Map<String, dynamic>? ?? {};
      final newPresences = raw.map((k, v) =>
          MapEntry(k, v is List ? List<dynamic>.from(v) : <dynamic>[v]));

      // Detect joins
      for (final entry in newPresences.entries) {
        if (!_presenceState.containsKey(entry.key)) {
          for (final cb in _presenceJoinCallbacks) {
            cb(entry.key, entry.value);
          }
        }
      }
      // Detect leaves
      for (final entry in _presenceState.entries) {
        if (!newPresences.containsKey(entry.key)) {
          for (final cb in _presenceLeaveCallbacks) {
            cb(entry.key, entry.value);
          }
        }
      }

      _presenceState
        ..clear()
        ..addAll(newPresences);

      final snapshot = Map<String, List<dynamic>>.unmodifiable(_presenceState);
      _eventController.add(RealtimePresenceEvent(channel: name, presences: snapshot));
      for (final cb in _presenceSyncCallbacks) {
        cb(snapshot);
      }
    } else if (msg['type'] == 'system') {
      _eventController.add(RealtimeSystemEvent(
        event: msg['event'] as String? ?? '',
        message: msg['message'] as String?,
      ));
    } else if (msg['type'] == 'error') {
      _eventController.add(RealtimeErrorEvent(
        code: msg['code'] as String? ?? 'unknown',
        message: msg['message'] as String? ?? 'Unknown error',
      ));
    }
  }

  void _setStatus(ChannelStatus s) {
    _status = s;
  }

  void dispose() {
    _eventController.close();
  }
}

// ─── RealtimeChannelManager ───────────────────────────────────────────────────

/// Manages the WebSocket connection and all channels. Used internally by
/// [OrbitNestRealtime].
// Reconnect tuning.
const int _kBaseReconnectDelayMs = 1000;
const int _kRateLimitedReconnectDelayMs = 10000;
const int _kMaxReconnectDelayMs = 60000;
// WS close code the gateway uses when it closes an abusive socket.
const int _kWsCloseRateLimited = 4029;

class RealtimeChannelManager {
  final String wsUrl;
  final String? apiKey;
  final String? userJwt;

  /// Supplies the current user access token at connect time (null = anon).
  final Future<String?> Function()? accessTokenProvider;

  /// Called once when the server rejects the socket's user JWT (close 4001),
  /// e.g. to refresh the session and [reconnect].
  final Future<void> Function()? onAuthRejected;

  WebSocketChannel? _ws;
  // onAuthRejected already ran since the last accepted connect (no refresh loop).
  bool _authRetried = false;
  Future<void>? _connecting;
  StreamSubscription? _sub;
  final Map<String, RealtimeChannel> _channels = {};
  bool _shouldReconnect = true;
  int _reconnectDelayMs = _kBaseReconnectDelayMs;
  Timer? _reconnectTimer;

  RealtimeChannelManager({
    required this.wsUrl,
    this.apiKey,
    this.userJwt,
    this.accessTokenProvider,
    this.onAuthRejected,
  });

  // ─── Lifecycle ───────────────────────────────────────────────────────────────

  /// Connect if needed. Completes only once the socket is really open and
  /// throws if it cannot be opened (so the reconnect backoff keeps growing).
  Future<void> _ensureConnected() {
    if (_ws != null) return Future.value();
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<void> _connect() async {
    final uri = Uri.parse(wsUrl);
    // Pass credentials via WS subprotocols rather than the URL query string so
    // they are not captured in proxy / gateway access logs.
    final protocols = ['orbitnest-realtime-v1'];
    if (apiKey != null) protocols.add('orbitnest.apikey.$apiKey');
    final jwt = await accessTokenProvider?.call() ?? userJwt;
    if (jwt != null) protocols.add('orbitnest.user-jwt.$jwt');

    final ws = WebSocketChannel.connect(uri, protocols: protocols);
    await ws.ready; // throws when the server is unreachable / handshake fails
    _ws = ws;

    _sub = ws.stream.listen(
      (data) {
        try {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          _route(msg);
        } catch (_) {}
      },
      onDone: () {
        final code = _ws?.closeCode;
        // Rejected user JWT (expired / revoked / clock skew): refresh once.
        if (code == 4001 && jwt != null && !_authRetried && onAuthRejected != null) {
          _authRetried = true;
          onAuthRejected!().catchError((_) {});
        }
        _ws = null;
        _sub = null;
        for (final ch in _channels.values) {
          ch._setStatus(ChannelStatus.disconnected);
        }
        // Stop reconnecting for normal/auth-failure closures.
        if (code == 1000 || code == 1001 || code == 4001) {
          _shouldReconnect = false;
        }
        if (_shouldReconnect && _channels.isNotEmpty) {
          // Rate-limited / policy closures → jump to long backoff floor.
          if (code == _kWsCloseRateLimited || code == 1008 || code == 1013) {
            if (_reconnectDelayMs < _kRateLimitedReconnectDelayMs) {
              _reconnectDelayMs = _kRateLimitedReconnectDelayMs;
            }
          }
          _scheduleReconnect();
        }
      },
      onError: (_) {
        _ws = null;
        _sub = null;
        for (final ch in _channels.values) {
          ch._setStatus(ChannelStatus.error);
        }
        if (_shouldReconnect && _channels.isNotEmpty) {
          _scheduleReconnect();
        }
      },
      cancelOnError: false,
    );

    // Activate all channels now that the socket is open.
    for (final ch in _channels.values) {
      ch._activate();
    }
  }

  /// Drop the current socket (without firing the reconnect handler) and open
  /// a new one if any channel is subscribed, picking up the current user token.
  Future<void> reconnect() async {
    await _sub?.cancel();
    _sub = null;
    await _ws?.sink.close();
    _ws = null;
    if (_channels.isEmpty) return;
    _shouldReconnect = true;
    try {
      await _ensureConnected();
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    // Small jitter so many clients don't reconnect at the same ms.
    final jitter = (DateTime.now().microsecondsSinceEpoch % 500);
    final delay = (_reconnectDelayMs + jitter).clamp(0, _kMaxReconnectDelayMs);
    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      _reconnectDelayMs =
          (_reconnectDelayMs * 2).clamp(0, _kMaxReconnectDelayMs);
      _ensureConnected().then((_) {
        _reconnectDelayMs = _kBaseReconnectDelayMs; // reset on success
      }).catchError((_) {
        // Keep backing off; the next scheduled attempt already uses the
        // doubled delay set above.
        if (_shouldReconnect && _channels.isNotEmpty) {
          _scheduleReconnect();
        }
      });
    });
  }

  void _send(Map<String, dynamic> msg) {
    _ws?.sink.add(jsonEncode(msg));
  }

  // ─── Channel management ───────────────────────────────────────────────────────

  Future<void> _subscribe(RealtimeChannel ch) async {
    _channels[ch.name] = ch;
    _shouldReconnect = true;
    if (_ws != null) {
      ch._activate();
      return;
    }
    try {
      await _ensureConnected(); // activates every registered channel
    } catch (_) {
      ch._setStatus(ChannelStatus.error);
      _scheduleReconnect();
    }
  }

  Future<void> _unsubscribe(RealtimeChannel ch) async {
    _channels.remove(ch.name);
    // The server keys subscriptions by full channel string and channels share
    // one socket, so keep any that a remaining channel still uses.
    final stillUsed = {for (final c in _channels.values) ...c._serverChannels};
    for (final channel in ch._serverChannels.difference(stillUsed)) {
      _send({
        'id': ch._msgId('unsub'),
        'type': 'unsubscribe',
        'channel': channel,
      });
    }
    if (_channels.isEmpty) {
      _shouldReconnect = false;
      await _ws?.sink.close();
      _ws = null;
    }
  }

  Future<void> _sendBroadcast(
      String channelName, String event, dynamic payload) async {
    await _ensureConnected();
    _send({
      'id': '$channelName#bc_${DateTime.now().microsecondsSinceEpoch}',
      'type': 'broadcast',
      'channel': 'broadcast:$channelName',
      'event': event,
      'payload': payload,
    });
  }

  // ─── Message routing ─────────────────────────────────────────────────────────

  void _route(Map<String, dynamic> msg) {
    final msgChannel = msg['channel'] as String?;
    if (msg['type'] == 'db_event' && msgChannel != null) {
      // channel is "table:schema.table" — find matching channel registrations
      for (final ch in _channels.values) {
        ch._dispatch(msg);
      }
    } else if (msg['type'] == 'broadcast' && msgChannel != null) {
      final channelName = msgChannel.replaceFirst('broadcast:', '');
      final target = _channels[channelName];
      if (target != null) target._dispatch(msg);
    } else if (msg['type'] == 'presence.state' && msgChannel != null) {
      final channelName = msgChannel.replaceFirst('broadcast:', '');
      final target = _channels[channelName];
      if (target != null) target._dispatch(msg);
    } else if (msg['type'] == 'system') {
      if (msg['event'] == 'connected') _authRetried = false;
      for (final ch in _channels.values) {
        ch._dispatch(msg);
      }
    } else if (msg['type'] == 'error') {
      // Route by the channel name we put in the request id; errors without a
      // ref (e.g. auth_failed) concern every channel.
      final ref = msg['ref'] as String?;
      final hash = ref?.lastIndexOf('#') ?? -1;
      final target = hash > 0 ? _channels[ref!.substring(0, hash)] : null;
      for (final ch in target != null ? [target] : _channels.values.toList()) {
        ch._dispatch(msg);
      }
    }
  }

  Future<void> _trackPresence(
      String channelName, Map<String, dynamic> state) async {
    await _ensureConnected();
    _send({
      'id': '$channelName#pt_${DateTime.now().microsecondsSinceEpoch}',
      'type': 'presence.track',
      'channel': 'broadcast:$channelName',
      'state': state,
    });
  }

  /// Drops presence only; the broadcast subscription stays. No ack is sent.
  Future<void> _untrackPresence(String channelName) async {
    _send({
      'id': '$channelName#pu_${DateTime.now().microsecondsSinceEpoch}',
      'type': 'presence.untrack',
      'channel': 'broadcast:$channelName',
    });
  }

  Future<void> dispose() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    await _ws?.sink.close();
    for (final ch in _channels.values) {
      ch.dispose();
    }
    _channels.clear();
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

List<String> _pgEventsToStrings(PgEvent event) {
  switch (event) {
    case PgEvent.insert:
      return ['INSERT'];
    case PgEvent.update:
      return ['UPDATE'];
    case PgEvent.delete:
      return ['DELETE'];
    case PgEvent.all:
      return ['INSERT', 'UPDATE', 'DELETE'];
  }
}
