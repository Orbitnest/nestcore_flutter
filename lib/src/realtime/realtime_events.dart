// Event models for the NestCore Realtime subsystem.

enum PgEvent { insert, update, delete, all }

/// A row-level change event delivered from the server.
class PgChangesPayload {
  final String op;
  final String schema;
  final String table;
  final Map<String, dynamic>? newRow;
  final Map<String, dynamic>? oldRow;
  final String commitTs;

  const PgChangesPayload({
    required this.op,
    required this.schema,
    required this.table,
    this.newRow,
    this.oldRow,
    required this.commitTs,
  });

  factory PgChangesPayload.fromJson(Map<String, dynamic> json) {
    return PgChangesPayload(
      op: json['op'] as String,
      schema: json['schema'] as String,
      table: json['table'] as String,
      newRow: json['new'] as Map<String, dynamic>?,
      oldRow: json['old'] as Map<String, dynamic>?,
      commitTs: json['commit_ts'] as String? ?? '',
    );
  }
}

/// A custom broadcast event.
class BroadcastPayload {
  final String event;
  final dynamic payload;

  const BroadcastPayload({required this.event, required this.payload});

  factory BroadcastPayload.fromJson(Map<String, dynamic> json) {
    return BroadcastPayload(
      event: json['event'] as String,
      payload: json['payload'],
    );
  }
}

/// Union type for anything delivered over a [RealtimeChannel].
sealed class RealtimeEvent {
  const RealtimeEvent();
}

class RealtimeDbEvent extends RealtimeEvent {
  final PgChangesPayload payload;
  const RealtimeDbEvent(this.payload);
}

class RealtimeBroadcastEvent extends RealtimeEvent {
  final BroadcastPayload payload;
  const RealtimeBroadcastEvent(this.payload);
}

class RealtimeSystemEvent extends RealtimeEvent {
  final String event;
  final String? message;
  const RealtimeSystemEvent({required this.event, this.message});
}

class RealtimeErrorEvent extends RealtimeEvent {
  final String code;
  final String message;
  const RealtimeErrorEvent({required this.code, required this.message});
}

/// Fired whenever the server sends a full presence roster snapshot.
class RealtimePresenceEvent extends RealtimeEvent {
  final String channel;

  /// Map of socketId → list of presence state objects for that socket.
  final Map<String, List<dynamic>> presences;

  const RealtimePresenceEvent({required this.channel, required this.presences});
}
