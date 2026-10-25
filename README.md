# NestCore Flutter

The official Flutter client for [NestCore](https://nestcore.io) — a Postgres-backed application platform. One SDK for authentication, database queries, realtime, storage, and edge functions, with a Supabase-style API.

The client is built on the BLoC pattern internally, but you don't need to know BLoC to use it: every feature is exposed through plain `async`/`await` methods. Reactive state streams are available when you want them.

## Contents

- [Installation](#installation)
- [Configuration](#configuration)
- [Quick start](#quick-start)
- [Authentication](#authentication)
- [Database](#database)
- [Storage](#storage)
- [Realtime](#realtime)
- [Edge functions](#edge-functions)
- [AI](#ai)
- [Analytics](#analytics)
- [Reactive state with BLoC](#reactive-state-with-bloc)
- [Error handling](#error-handling)
- [Migrating from Supabase](#migrating-from-supabase)
- [API surface](#api-surface)

## Installation

```yaml
dependencies:
  nestcore_flutter: ^1.9.0
```

```bash
flutter pub get
```

### Coming from `orbitnest_studio_flutter`

The package was renamed in 1.9.0 when OrbitNest became NestCore. To upgrade, replace the `orbitnest_studio_flutter` dependency with `nestcore_flutter`; nothing else is required right away:

- **Old names still work.** `OrbitNestClient`, `OrbitNestException`, `OrbitNestAuth` and the other `OrbitNest*` types are deprecated aliases of their `NestCore*` replacements, so `OrbitNestClient.create(...)` and `on OrbitNestException catch` keep compiling (with deprecation warnings).
- **The old import path still works.** `import 'package:nestcore_flutter/orbitnest_studio_flutter.dart';` re-exports the package. Switch to `package:nestcore_flutter/nestcore_flutter.dart` when convenient.
- **Old `.env` names still work.** `ORBITNEST_ANON_KEY`, `ORBITNEST_DEBUG`, `ORBITNEST_API_TIMEOUT` and `ORBITNEST_API_URL` are read when the `NESTCORE_*` variable is not set.
- **Users stay signed in.** The SDK moves sessions stored under the old `orbitnest_*` secure-storage keys to the new `nestcore_*` keys on first launch.
- The default API URL is now `https://api.nestcore.io`.

The aliases will be removed in a future major version.

## Configuration

A client app authenticates with your project's **anon key** — a public, RLS-protected key. The project slug and API URL are encoded inside the anon key JWT and resolved automatically; you don't set them separately.

Copy `.env.example` to `.env` and set your key:

```env
# From NestCore → Settings → API Keys
NESTCORE_ANON_KEY=your_anon_key_here

# Verbose SDK logging — leave false/unset in production
NESTCORE_DEBUG=false

# Optional. HTTP timeout in ms (default 180000). Local dev base URL override.
# NESTCORE_API_TIMEOUT=180000
# NESTCORE_API_URL=http://localhost:3002
```

Register `.env` as an asset in your app's `pubspec.yaml` (or skip `.env` entirely and pass `anonKey:` to `NestCoreClient.create`):

```yaml
flutter:
  assets:
    - .env
```

> **Security.** This is a client SDK. Ship **only** the anon key. A service-role / admin key is server-side and would be extractable from the installed app binary, so it must never be bundled. Backend management — creating tables, policies, functions, or jobs — is done from the NestCore dashboard or admin tooling, not from this SDK.

## Quick start

```dart
import 'package:nestcore_flutter/nestcore_flutter.dart';

Future<void> main() async {
  await EnvConfig.initialize();           // load .env
  final nestcore = NestCoreClient.create();

  // Or pass the key explicitly:
  // final nestcore = NestCoreClient.create(anonKey: 'your_anon_key');

  final users = await nestcore
      .from('users')
      .select('id, name, email')
      .eq('status', 'active')
      .limit(20)
      .execute();

  print(users.data);
  nestcore.dispose();
}
```

The client exposes each capability as a sub-API:

```dart
nestcore.auth        // authentication
nestcore.database    // database CRUD + query builder
nestcore.storage     // file storage
nestcore.realtime    // live subscriptions, broadcast, presence
nestcore.functions   // edge function invocation
nestcore.analytics   // events, screens, crashes
```

## Authentication

NestCore supports password, email OTP, SMS OTP, TOTP-based multi-factor auth, and passkeys (WebAuthn). All methods return plain maps/objects and throw `AuthException` on failure.

### Password

```dart
// Sign up sends a verification OTP to the email.
await nestcore.auth.signUp(email: 'user@example.com', password: 'secret123');

final result = await nestcore.auth.signInWithPassword(
  email: 'user@example.com',
  password: 'secret123',
);
if (result['mfa_required'] == true) {
  // see "Multi-factor authentication" below
} else {
  final user = User.fromJson(result['user']);
}

// Forgot password: emails a code, then reset with it. The user signs in again
// afterwards (resetPassword returns {email, message}, no session).
await nestcore.auth.resetPasswordForEmail('user@example.com');
await nestcore.auth.resetPassword(
  email: 'user@example.com',
  token: '123456',
  newPassword: 'newSecret123',
);

// Changing the password or email of a signed-in user needs the current password.
await nestcore.auth.updateUser(
  password: 'newSecret456',
  currentPassword: 'newSecret123',
);
```

### Email OTP

```dart
await nestcore.auth.signInWithEmail('user@example.com');   // sends a code
await nestcore.auth.verifySignIn(email: 'user@example.com', otp: '123456');

// Sign-up variants: signUpWithEmail(...) then verifySignUp(...).
```

### SMS OTP

Requires SMS to be configured for your project. Phone numbers are E.164 (e.g. `+15555550123`).

```dart
await nestcore.auth.signInWithSms('+15555550123');
await nestcore.auth.verifySmsOtp(phone: '+15555550123', code: '123456');
// Signed in: isAuthenticated, currentUser and onAuthStateChange update.
```

Sending is rate limited per phone (`AuthException.code == 'SMS_RATE_LIMITED'`, HTTP 429); too many wrong codes give `OTP_RATE_LIMITED`.

### Multi-factor authentication (TOTP)

```dart
// Enroll an authenticator app.
final enroll = await nestcore.auth.enrollMfaTotp(friendlyName: 'My phone');
// enroll['qr_code'] / enroll['otpauth_url'] — show to the user to scan.

final verified = await nestcore.auth.verifyMfaEnrollment(
  factorId: enroll['factor_id'],
  code: '123456',
);
final recoveryCodes = verified['recovery_codes']; // shown once — store safely

// When a password sign-in is MFA-gated, complete it with the challenge token:
await nestcore.auth.verifyMfa(challengeToken: '...', code: '123456');

await nestcore.auth.listMfaFactors();

// Once a factor is verified, these need a current TOTP or recovery code:
await nestcore.auth.regenerateMfaRecoveryCodes(code: '123456');
await nestcore.auth.unenrollMfa(factorId: '...', code: '123456');
await nestcore.auth.enrollMfaTotp(friendlyName: 'Backup phone', code: '123456');
```

### Passkeys (WebAuthn)

```dart
if (await nestcore.auth.isPasskeySupported()) {
  // New user: create an account and register a passkey in one ceremony.
  await nestcore.auth.signUpWithPasskey(email: 'user@example.com');

  // Returning user:
  await nestcore.auth.signInWithPasskey(identifier: 'user@example.com');

  // For an already-authenticated user:
  await nestcore.auth.registerPasskey(deviceName: 'iPhone');
  await nestcore.auth.listPasskeys();
  await nestcore.auth.renamePasskey(deviceId: '...', deviceName: 'Work phone');
  await nestcore.auth.revokePasskey(deviceId: '...');
}
```

### Session

```dart
nestcore.auth.isAuthenticated;        // bool
nestcore.auth.currentUser;            // User?
nestcore.auth.currentSession;         // Session?
await nestcore.auth.refreshSession();   // throws AuthException on failure
await nestcore.auth.signOut();
await nestcore.auth.deleteUser();       // deletes the account, then signs out locally

// React to changes (optional).
nestcore.auth.onAuthStateChange.listen((state) { /* ... */ });

// Fires when the server rejects the refresh token (the session is over).
nestcore.onSessionExpired.listen((_) => goToLogin());
```

Sessions are stored in encrypted device storage. Tokens refresh automatically ahead of expiry. If a refresh fails because the device is offline or the server is down, the stored session is kept and the refresh is retried on the next request. A plain `401`/`403` on a data or function call (for example an anonymous user calling `update`) is thrown to the caller and does **not** fire `onSessionExpired`.

## Database

A Supabase-style query builder plus direct CRUD helpers over the NestCore data API. Reads work with the anon key; `update`/`delete` need a signed-in user. Row Level Security applies.

### Query builder

```dart
final posts = await nestcore
    .from('posts')
    .select('id, title, created_at')     // plain column list, or '*'
    .eq('published', true)
    .gte('created_at', '2024-01-01')
    .order('created_at', ascending: false)
    .range(0, 49)                         // rows 0..49
    .execute();
print(posts.data);   // rows
print(posts.count);  // total matching rows

await nestcore.from('users').insert({'name': 'Jane', 'email': 'jane@x.io'});
await nestcore.from('users').insert([{'name': 'A'}, {'name': 'B'}]);

// Filters come first; update()/delete() run immediately. Equality filters only.
await nestcore.from('users').eq('id', 1).update({'status': 'inactive'});
await nestcore.from('users').eq('id', 1).delete();
```

Filters: `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `like`, `ilike`, `inFilter`, `isFilter` / `isNull` (`null`, `true`, `false`), `match`, `not(col, 'eq', v)`.
Modifiers: `order` (one column), `limit`, `range`, `single`, `maybeSingle`. A page holds at most 100 rows.

Full-text and vector search chain like the other filters (the query then runs as one parameterized SELECT; `count` is the number of rows returned):

```dart
final hits = await nestcore.from('posts')
    .eq('published', true)
    .textSearch('body', 'refund -gift', type: 'websearch') // or 'plain', 'phrase'; config: 'english'
    .limit(20)
    .execute();

final near = await nestcore.from('docs').nearest('embedding', queryVector, metric: 'cosine', limit: 5).execute();
```

Limits of the API, enforced by the SDK (they throw instead of silently returning wrong rows):
- `contains`, `containedBy`, `overlaps`, the `range*` filters, `or`, `and`, `isNotNull` and `upsert` throw `UnsupportedError`. Use `database.sql()` for those queries.
- `inFilter` values cannot contain `,`.
- `select()` takes plain column names (no aliases or embedded relations).
- `update()`/`delete()` require at least one filter; they match rows with `column = value` (AND).

### Direct CRUD

```dart
final res = await nestcore.database.select('users',
  columns: 'id, name', filters: {'status': 'active'},
  orderBy: ['created_at.desc'], limit: 10, offset: 20);
print(res.data);

await nestcore.database.insert('users', {'name': 'Sam'});
await nestcore.database.update('users', {'age': 31}, filters: {'id': 1});
await nestcore.database.delete('users', filters: {'id': 1});

// insertMany sends one request per row (not atomic).
await nestcore.database.insertMany('users', [{'name': 'A'}, {'name': 'B'}]);
// updateMany / deleteMany hit every row matching ALL filters (column = value).
final upd = await nestcore.database.updateMany('users', {'tier': 'pro'}, filters: {'plan': 'paid'});
final del = await nestcore.database.deleteMany('posts', filters: {'author_id': 12});
print(del.count); // rows deleted
```

### Vector search (pgvector)

```dart
final matches = await nestcore.database.vectorSearch(
  'documents',
  'embedding',
  [0.12, 0.04, /* ... */],
  metric: 'cosine',   // 'l2' (default), 'cosine', or 'ip'
  limit: 5,
);
```

### Semantic search (automatic embeddings)

For a column embedded with automatic embeddings (NestCore → AI → Embeddings). Needs a signed-in user; RLS applies.

```dart
final r = await nestcore.from('articles')
    .eq('published', true)
    .limit(5)                                  // k
    .semantic('body_embedding', 'how do I reset my password?', hybridColumn: 'body');
for (final row in r.rows) print('${row['title']} ${row['_similarity']}');
```

### Raw SQL

Placeholders are `$1`, `$2`, … The anon key (with or without a signed-in user) may run `SELECT` and `INSERT`.

```dart
final result = await nestcore.database.sql(
  r'SELECT name, COUNT(*) FROM posts GROUP BY name ORDER BY count DESC LIMIT $1',
  parameters: [10],
);
print(result.data);  // rows
print(result.count); // rows affected
```

## Storage

Bucket-scoped file operations. `getPublicUrl` builds a URL locally (no network) and can request on-the-fly image transforms.

```dart
final bucket = nestcore.storage.from('avatars');

await bucket.upload(path: 'u/1.png', bytes: pngBytes, contentType: 'image/png', upsert: true);
final bytes = await bucket.download('u/1.png');
final files = await bucket.list(prefix: 'u/');
await bucket.remove(['u/1.png']);

final url = bucket.getPublicUrl('u/1.png', transform: StorageTransform(
  width: 200, height: 200, format: 'webp', quality: 80, fit: 'cover',
));
```

## Realtime

Subscribe to Postgres changes, send broadcast messages, and track presence over a single WebSocket.

```dart
final channel = nestcore.realtime.channel('room:42');

channel
  .onPostgresChanges(
    event: PgEvent.insert,
    table: 'messages',
    filter: RealtimeFilter(column: 'room_id', op: 'eq', value: '42'),
    callback: (payload) => print('new message: ${payload.newRow}'),
  )
  .onBroadcast(event: 'typing', callback: (p) => print(p.payload))
  .onPresenceSync((state) => print('online: ${state.keys}'));

await channel.subscribe();
await channel.track({'user': 'jane'});           // presence
await channel.send(event: 'typing', payload: {'user': 'jane'});

await channel.unsubscribe();
await nestcore.realtime.dispose();
```

When a user is signed in the socket carries their access token, so row events respect RLS for that user (anonymous sockets only see rows visible to `anon`). The socket reconnects automatically on sign-in / sign-out. `DELETE` events and tables without a primary key are not delivered to client sockets. Server errors (for example `not_subscribed`, `limit_exceeded`) arrive on `channel.events` as `RealtimeErrorEvent`.

## Edge functions

The SDK **invokes** edge functions. (Creating and managing functions is done in the NestCore dashboard, not from the client.)

```dart
final res = await nestcore.functions.invoke('send-email', body: {
  'to': 'user@example.com',
  'subject': 'Welcome',
});
print(res.data);

// HTTP-verb helpers:
await nestcore.functions.get('health');
await nestcore.functions.post('charge', body: {'amount': 100});
await nestcore.functions.put('profile', body: {'name': 'Jane'});
await nestcore.functions.delete('session');

// Shorthand on the client:
await nestcore.function('send-email', params: {'to': 'user@example.com'});
```

## AI

Chat, streaming, tool calls and embeddings through the project's own provider keys (NestCore → Project Settings → AI). Calls need a signed-in user.

```dart
final r = await nestcore.ai.chat(messages: [AiMessage.user('Summarise my last order')]);

await for (final ev in nestcore.ai.chatStream(messages: history)) {
  switch (ev) {
    case AiTextDelta(:final text): setState(() => reply += text);
    case AiToolCallEvent(:final call): pending.add(call);
    case AiStreamDone(): break;
    case AiStreamError(:final code, :final message): showError('$code $message');
  }
}

final e = await nestcore.ai.embed(['first', 'second']); // 768 dimensions
```

Tool calls: answer each `r.toolCalls` entry with `AiMessage.toolResult(call, result)` after appending `AiMessage.fromResult(r)` to the history, then chat again. Cancelling the stream subscription stops the reply at the server. Errors from `chat`/`embed` are `AiException` (`code`, `statusCode`, `body`).

### Memory, collections and threads

```dart
// Memory: facts about the signed-in user, searched by meaning.
await nestcore.memory.add('Prefers vegetarian recipes', kind: 'preference');
final m = await nestcore.memory.search('what should I cook?');
await nestcore.memory.forget(); // delete everything about this user

// Collections: documents chunked, embedded and searched (vector + keyword).
final kb = nestcore.collections.from('handbook');
await kb.ingest(AiDocumentSource.text(notes), title: 'Notes', wait: true); // needs userIngest for users
final hits = await kb.search('How do refunds work?', k: 5);

// Threads: saved conversations; replies stream and are stored as they arrive.
final t = await nestcore.ai.threads.create(title: 'Trip ideas');
await for (final ev in nestcore.ai.threads.from(t.id).run(
    input: 'Plan a weekend in Oslo', memory: true, collections: ['handbook'])) {
  switch (ev) {
    case ThreadRunDelta(:final text): setState(() => reply += text);
    case ThreadRunCitation(:final citation): sources.add(citation);
    case ThreadRunError(:final message): showError(message);
    default: break;
  }
}
final history = await nestcore.ai.threads.from(t.id).messages();
```

Creating collections, adding shared documents, `memory.subjects()`/`reembed()` and `ai.traces()` need the service-role key, which an app never holds (use the NestCore console, the Node SDK or the CLI). `runOnce()` waits for the finished message instead of streaming. Failures throw `AiException`; `run()` yields a `ThreadRunError` instead.

## Analytics

```dart
nestcore.analytics.identify('user-123');
nestcore.analytics.track('purchase', properties: {'amount': 9.99});
nestcore.analytics.screen('Home');
nestcore.analytics.crash(error, stackTrace: stackTrace);
```

Events are batched and sent every few seconds; `dispose()` flushes the queue.

## Reactive state with BLoC

Auth exposes a state stream for UI that reacts automatically — the `async`/`await` API above covers most apps.

```dart
nestcore.auth.onAuthStateChange.listen((state) { /* AuthAuthenticatedState, AuthUnauthenticatedState, ... */ });
```

The BLoC classes (`AuthBloc`, `DatabaseBloc`, `FunctionsBloc`) are exported for advanced setups that build their own. The `nestcore.database` methods call the API directly, so `nestcore.database.onStateChange` only reflects events you dispatch to a `DatabaseBloc` yourself.

## Error handling

All operations throw a subclass of `NestCoreException` on failure:

```dart
try {
  await nestcore.auth.signInWithPassword(email: e, password: p);
} on AuthException catch (e) {
  print('${e.code}: ${e.message}');
} on DatabaseException catch (e) {
  print(e.message);
} on FunctionException catch (e) {
  print(e.message);
}
```

Transient network failures (timeouts, connection errors, and `408`/`429`/`5xx` responses) are retried automatically with exponential backoff (file uploads are not retried). Logs redact tokens, keys, and other sensitive fields in both debug and release builds.

## Migrating from Supabase

The query builder and client shape follow `supabase_flutter`. Simple filters, ordering and paging carry over; see [Database](#database) for what the NestCore data API does not support (upsert, `or`/`and`, JSON/array/range filters, embedded selects).

```dart
// Before
await Supabase.initialize(url: url, anonKey: key);
final db = Supabase.instance.client;

// After
await EnvConfig.initialize();
final db = NestCoreClient.create();

// Similar query syntax (end the chain with execute()):
final rows = await db.from('users').select('*').eq('status', 'active').execute();
```

## API surface

| Area | Entry point | Notes |
|------|-------------|-------|
| Auth | `nestcore.auth` | password, email/SMS OTP, MFA (TOTP), passkeys, sessions |
| Database | `nestcore.from(table)`, `nestcore.database` | query builder, full-text, pgvector, semantic search, CRUD, raw SQL |
| AI | `nestcore.ai`, `nestcore.memory`, `nestcore.collections` | chat/stream/embed, threads, memory, document collections |
| Storage | `nestcore.storage.from(bucket)` | upload, download, list, remove, public URLs + transforms |
| Realtime | `nestcore.realtime.channel(name)` | Postgres changes, broadcast, presence |
| Functions | `nestcore.functions` | invoke only (`invoke`, `call`, `get`/`post`/`put`/`delete`) |
| Analytics | `nestcore.analytics` | `identify`, `track`, `screen`, `crash` |
| Config | `EnvConfig` | `.env` loading, runtime settings |

Call `nestcore.dispose()` when the client is no longer needed to flush analytics and release the HTTP client and any open realtime connection.

`nestcore.jobs` and `nestcore.migrations` are deprecated: those routes need the console's admin API (jobs) or do not exist (migrations), so they cannot work from an app. Use the NestCore console or CLI.

## License

MIT — see [LICENSE](LICENSE).
