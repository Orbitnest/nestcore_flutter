# OrbitNest Studio Flutter

The official Flutter client for [OrbitNest Studio](https://studio.orbitnest.io) — a Postgres-backed application platform. One SDK for authentication, database queries, realtime, storage, and edge functions, with a Supabase-style API.

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
- [Analytics](#analytics)
- [Reactive state with BLoC](#reactive-state-with-bloc)
- [Error handling](#error-handling)
- [Migrating from Supabase](#migrating-from-supabase)
- [API surface](#api-surface)

## Installation

```yaml
dependencies:
  orbitnest_studio_flutter: ^1.7.0
```

```bash
flutter pub get
```

## Configuration

A client app authenticates with your project's **anon key** — a public, RLS-protected key. The project slug and API URL are encoded inside the anon key JWT and resolved automatically; you don't set them separately.

Copy `.env.example` to `.env` and set your key:

```env
# From OrbitNest Studio → Settings → API Keys
ORBITNEST_ANON_KEY=your_anon_key_here

# Verbose SDK logging — leave false/unset in production
ORBITNEST_DEBUG=false

# Optional. HTTP timeout in ms (default 180000). Local dev base URL override.
# ORBITNEST_API_TIMEOUT=180000
# ORBITNEST_API_URL=http://localhost:3002
```

Register `.env` as an asset in your app's `pubspec.yaml` (or skip `.env` entirely and pass `anonKey:` to `OrbitNestClient.create`):

```yaml
flutter:
  assets:
    - .env
```

> **Security.** This is a client SDK. Ship **only** the anon key. A service-role / admin key is server-side and would be extractable from the installed app binary, so it must never be bundled. Backend management — creating tables, policies, functions, or jobs — is done from the OrbitNest Studio dashboard or admin tooling, not from this SDK.

## Quick start

```dart
import 'package:orbitnest_studio_flutter/orbitnest_studio_flutter.dart';

Future<void> main() async {
  await EnvConfig.initialize();           // load .env
  final orbitnest = OrbitNestClient.create();

  // Or pass the key explicitly:
  // final orbitnest = OrbitNestClient.create(anonKey: 'your_anon_key');

  final users = await orbitnest
      .from('users')
      .select('id, name, email')
      .eq('status', 'active')
      .limit(20)
      .execute();

  print(users.data);
  orbitnest.dispose();
}
```

The client exposes each capability as a sub-API:

```dart
orbitnest.auth        // authentication
orbitnest.database    // database CRUD + query builder
orbitnest.storage     // file storage
orbitnest.realtime    // live subscriptions, broadcast, presence
orbitnest.functions   // edge function invocation
orbitnest.analytics   // events, screens, crashes
```

## Authentication

OrbitNest supports password, email OTP, SMS OTP, TOTP-based multi-factor auth, and passkeys (WebAuthn). All methods return plain maps/objects and throw `AuthException` on failure.

### Password

```dart
// Sign up sends a verification OTP to the email.
await orbitnest.auth.signUp(email: 'user@example.com', password: 'secret123');

final result = await orbitnest.auth.signInWithPassword(
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
await orbitnest.auth.resetPasswordForEmail('user@example.com');
await orbitnest.auth.resetPassword(
  email: 'user@example.com',
  token: '123456',
  newPassword: 'newSecret123',
);

// Changing the password or email of a signed-in user needs the current password.
await orbitnest.auth.updateUser(
  password: 'newSecret456',
  currentPassword: 'newSecret123',
);
```

### Email OTP

```dart
await orbitnest.auth.signInWithEmail('user@example.com');   // sends a code
await orbitnest.auth.verifySignIn(email: 'user@example.com', otp: '123456');

// Sign-up variants: signUpWithEmail(...) then verifySignUp(...).
```

### SMS OTP

Requires SMS to be configured for your project. Phone numbers are E.164 (e.g. `+15555550123`).

```dart
await orbitnest.auth.signInWithSms('+15555550123');
await orbitnest.auth.verifySmsOtp(phone: '+15555550123', code: '123456');
// Signed in: isAuthenticated, currentUser and onAuthStateChange update.
```

Sending is rate limited per phone (`AuthException.code == 'SMS_RATE_LIMITED'`, HTTP 429); too many wrong codes give `OTP_RATE_LIMITED`.

### Multi-factor authentication (TOTP)

```dart
// Enroll an authenticator app.
final enroll = await orbitnest.auth.enrollMfaTotp(friendlyName: 'My phone');
// enroll['qr_code'] / enroll['otpauth_url'] — show to the user to scan.

final verified = await orbitnest.auth.verifyMfaEnrollment(
  factorId: enroll['factor_id'],
  code: '123456',
);
final recoveryCodes = verified['recovery_codes']; // shown once — store safely

// When a password sign-in is MFA-gated, complete it with the challenge token:
await orbitnest.auth.verifyMfa(challengeToken: '...', code: '123456');

await orbitnest.auth.listMfaFactors();

// Once a factor is verified, these need a current TOTP or recovery code:
await orbitnest.auth.regenerateMfaRecoveryCodes(code: '123456');
await orbitnest.auth.unenrollMfa(factorId: '...', code: '123456');
await orbitnest.auth.enrollMfaTotp(friendlyName: 'Backup phone', code: '123456');
```

### Passkeys (WebAuthn)

```dart
if (await orbitnest.auth.isPasskeySupported()) {
  // New user: create an account and register a passkey in one ceremony.
  await orbitnest.auth.signUpWithPasskey(email: 'user@example.com');

  // Returning user:
  await orbitnest.auth.signInWithPasskey(identifier: 'user@example.com');

  // For an already-authenticated user:
  await orbitnest.auth.registerPasskey(deviceName: 'iPhone');
  await orbitnest.auth.listPasskeys();
  await orbitnest.auth.renamePasskey(deviceId: '...', deviceName: 'Work phone');
  await orbitnest.auth.revokePasskey(deviceId: '...');
}
```

### Session

```dart
orbitnest.auth.isAuthenticated;        // bool
orbitnest.auth.currentUser;            // User?
orbitnest.auth.currentSession;         // Session?
await orbitnest.auth.refreshSession();   // throws AuthException on failure
await orbitnest.auth.signOut();
await orbitnest.auth.deleteUser();       // deletes the account, then signs out locally

// React to changes (optional).
orbitnest.auth.onAuthStateChange.listen((state) { /* ... */ });

// Fires when the server rejects the refresh token (the session is over).
orbitnest.onSessionExpired.listen((_) => goToLogin());
```

Sessions are stored in encrypted device storage. Tokens refresh automatically ahead of expiry. If a refresh fails because the device is offline or the server is down, the stored session is kept and the refresh is retried on the next request. A plain `401`/`403` on a data or function call (for example an anonymous user calling `update`) is thrown to the caller and does **not** fire `onSessionExpired`.

## Database

A Supabase-style query builder plus direct CRUD helpers over the OrbitNest data API. Reads work with the anon key; `update`/`delete` need a signed-in user. Row Level Security applies.

### Query builder

```dart
final posts = await orbitnest
    .from('posts')
    .select('id, title, created_at')     // plain column list, or '*'
    .eq('published', true)
    .gte('created_at', '2024-01-01')
    .order('created_at', ascending: false)
    .range(0, 49)                         // rows 0..49
    .execute();
print(posts.data);   // rows
print(posts.count);  // total matching rows

await orbitnest.from('users').insert({'name': 'Jane', 'email': 'jane@x.io'});
await orbitnest.from('users').insert([{'name': 'A'}, {'name': 'B'}]);

// Filters come first; update()/delete() run immediately. Equality filters only.
await orbitnest.from('users').eq('id', 1).update({'status': 'inactive'});
await orbitnest.from('users').eq('id', 1).delete();
```

Filters: `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `like`, `ilike`, `inFilter`, `isFilter` / `isNull` (`null`, `true`, `false`), `match`, `not(col, 'eq', v)`.
Modifiers: `order` (one column), `limit`, `range`, `single`, `maybeSingle`. A page holds at most 100 rows.

Limits of the API, enforced by the SDK (they throw instead of silently returning wrong rows):
- `contains`, `containedBy`, `overlaps`, the `range*` filters, `textSearch`, `or`, `and`, `isNotNull` and `upsert` throw `UnsupportedError`. Use `database.sql()` for those queries.
- `inFilter` values cannot contain `,`.
- `select()` takes plain column names (no aliases or embedded relations).
- `update()`/`delete()` require at least one filter; they match rows with `column = value` (AND).

### Direct CRUD

```dart
final res = await orbitnest.database.select('users',
  columns: 'id, name', filters: {'status': 'active'},
  orderBy: ['created_at.desc'], limit: 10, offset: 20);
print(res.data);

await orbitnest.database.insert('users', {'name': 'Sam'});
await orbitnest.database.update('users', {'age': 31}, filters: {'id': 1});
await orbitnest.database.delete('users', filters: {'id': 1});

// insertMany sends one request per row (not atomic).
await orbitnest.database.insertMany('users', [{'name': 'A'}, {'name': 'B'}]);
// updateMany / deleteMany hit every row matching ALL filters (column = value).
final upd = await orbitnest.database.updateMany('users', {'tier': 'pro'}, filters: {'plan': 'paid'});
final del = await orbitnest.database.deleteMany('posts', filters: {'author_id': 12});
print(del.count); // rows deleted
```

### Vector search (pgvector)

```dart
final matches = await orbitnest.database.vectorSearch(
  'documents',
  'embedding',
  [0.12, 0.04, /* ... */],
  metric: 'cosine',   // 'l2' (default), 'cosine', or 'ip'
  limit: 5,
);
```

### Raw SQL

Placeholders are `$1`, `$2`, … The anon key (with or without a signed-in user) may run `SELECT` and `INSERT`.

```dart
final result = await orbitnest.database.sql(
  r'SELECT name, COUNT(*) FROM posts GROUP BY name ORDER BY count DESC LIMIT $1',
  parameters: [10],
);
print(result.data);  // rows
print(result.count); // rows affected
```

## Storage

Bucket-scoped file operations. `getPublicUrl` builds a URL locally (no network) and can request on-the-fly image transforms.

```dart
final bucket = orbitnest.storage.from('avatars');

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
final channel = orbitnest.realtime.channel('room:42');

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
await orbitnest.realtime.dispose();
```

When a user is signed in the socket carries their access token, so row events respect RLS for that user (anonymous sockets only see rows visible to `anon`). The socket reconnects automatically on sign-in / sign-out. `DELETE` events and tables without a primary key are not delivered to client sockets. Server errors (for example `not_subscribed`, `limit_exceeded`) arrive on `channel.events` as `RealtimeErrorEvent`.

## Edge functions

The SDK **invokes** edge functions. (Creating and managing functions is done in the OrbitNest Studio dashboard, not from the client.)

```dart
final res = await orbitnest.functions.invoke('send-email', body: {
  'to': 'user@example.com',
  'subject': 'Welcome',
});
print(res.data);

// HTTP-verb helpers:
await orbitnest.functions.get('health');
await orbitnest.functions.post('charge', body: {'amount': 100});
await orbitnest.functions.put('profile', body: {'name': 'Jane'});
await orbitnest.functions.delete('session');

// Shorthand on the client:
await orbitnest.function('send-email', params: {'to': 'user@example.com'});
```

## Analytics

```dart
orbitnest.analytics.identify('user-123');
orbitnest.analytics.track('purchase', properties: {'amount': 9.99});
orbitnest.analytics.screen('Home');
orbitnest.analytics.crash(error, stackTrace: stackTrace);
```

Events are batched and sent every few seconds; `dispose()` flushes the queue.

## Reactive state with BLoC

Auth exposes a state stream for UI that reacts automatically — the `async`/`await` API above covers most apps.

```dart
orbitnest.auth.onAuthStateChange.listen((state) { /* AuthAuthenticatedState, AuthUnauthenticatedState, ... */ });
```

The BLoC classes (`AuthBloc`, `DatabaseBloc`, `FunctionsBloc`) are exported for advanced setups that build their own. The `orbitnest.database` methods call the API directly, so `orbitnest.database.onStateChange` only reflects events you dispatch to a `DatabaseBloc` yourself.

## Error handling

All operations throw a subclass of `OrbitNestException` on failure:

```dart
try {
  await orbitnest.auth.signInWithPassword(email: e, password: p);
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

The query builder and client shape follow `supabase_flutter`. Simple filters, ordering and paging carry over; see [Database](#database) for what the OrbitNest data API does not support (upsert, `or`/`and`, JSON/array/range filters, embedded selects).

```dart
// Before
await Supabase.initialize(url: url, anonKey: key);
final db = Supabase.instance.client;

// After
await EnvConfig.initialize();
final db = OrbitNestClient.create();

// Similar query syntax (end the chain with execute()):
final rows = await db.from('users').select('*').eq('status', 'active').execute();
```

## API surface

| Area | Entry point | Notes |
|------|-------------|-------|
| Auth | `orbitnest.auth` | password, email/SMS OTP, MFA (TOTP), passkeys, sessions |
| Database | `orbitnest.from(table)`, `orbitnest.database` | query builder, CRUD, pgvector, raw SQL |
| Storage | `orbitnest.storage.from(bucket)` | upload, download, list, remove, public URLs + transforms |
| Realtime | `orbitnest.realtime.channel(name)` | Postgres changes, broadcast, presence |
| Functions | `orbitnest.functions` | invoke only (`invoke`, `call`, `get`/`post`/`put`/`delete`) |
| Analytics | `orbitnest.analytics` | `identify`, `track`, `screen`, `crash` |
| Config | `EnvConfig` | `.env` loading, runtime settings |

Call `orbitnest.dispose()` when the client is no longer needed to flush analytics and release the HTTP client and any open realtime connection.

`orbitnest.jobs` and `orbitnest.migrations` are deprecated: those routes need the Studio admin API (jobs) or do not exist (migrations), so they cannot work from an app. Use Studio or the OrbitNest CLI.

## License

MIT — see [LICENSE](LICENSE).
