## [1.9.0]

### Changed — OrbitNest is now NestCore
- **The package is renamed `orbitnest_studio_flutter` → `nestcore_flutter`** (repository: https://github.com/Orbitnest/nestcore_flutter). Replace the dependency in your `pubspec.yaml`; the main import is now `package:nestcore_flutter/nestcore_flutter.dart`. Releases of `orbitnest_studio_flutter` stop at 1.8.0.
- Every public `OrbitNest*` type is now `NestCore*`: `NestCoreClient`, `NestCoreAuth`, `NestCoreDatabase`, `NestCoreFunctions`, `NestCoreRealtime`, `NestCoreStorage`, `NestCoreAi`, `NestCoreMemory`, `NestCoreCollections`, `NestCoreException`, `NestCoreConstants`, `NestCoreLogger` (plus the internal `NestCoreHttpClient` / `NestCoreAnalytics`).
- The default API base URL is `https://api.nestcore.io`.
- `.env` settings are `NESTCORE_ANON_KEY`, `NESTCORE_DEBUG`, `NESTCORE_API_TIMEOUT` and `NESTCORE_API_URL`.
- The SDK identifies itself as `X-Client-Info: nestcore-flutter/<version>`; log tags (`NestCore`, `NestCore.HTTP`) and error texts (`NestCoreException(...)`) say NestCore.
- Realtime offers the `nestcore-realtime-v1` / `nestcore.apikey.<key>` / `nestcore.user-jwt.<jwt>` WebSocket subprotocols (the API accepts both these and the old `orbitnest.*` ones).
- Secure-storage keys are now `nestcore_session`, `nestcore_access_token`, `nestcore_refresh_token`, `nestcore_api_key` and `nestcore_project_slug`.

### Compatibility — nothing breaks on upgrade
- **Deprecated aliases:** `OrbitNestClient`, `OrbitNestAuth`, `OrbitNestDatabase`, `OrbitNestFunctions`, `OrbitNestRealtime`, `OrbitNestStorage`, `OrbitNestAi`, `OrbitNestMemory`, `OrbitNestCollections`, `OrbitNestException`, `OrbitNestConstants` and `OrbitNestLogger` are `typedef`s of the new types, so `OrbitNestClient.create(...)`, `on OrbitNestException catch`, `OrbitNestConstants.version` and friends keep compiling (with a deprecation warning).
- **Old import path:** `package:nestcore_flutter/orbitnest_studio_flutter.dart` re-exports the package (deprecated).
- **Old env names:** each `ORBITNEST_*` variable is still read when its `NESTCORE_*` counterpart is unset or empty.
- **Users stay signed in:** on first use the `TokenManager` moves values stored under the old `orbitnest_*` secure-storage keys to the `nestcore_*` keys (only where the new key is empty) and deletes the old keys; sign-out clears both sets.
- The aliases, the old import path and the `ORBITNEST_*` fallback will be removed in a future major version.

## [1.8.0]

### Added — AI data (parity with the Node/Web SDK)
- `client.memory`: `add` (dedupes near-identical memories unless `dedupe: false`), `search` (`similarity`, `score`, `degraded` keyword fallback), `list`, `get`, `update`, `remove`, `forget`, and service-key `subjects` / `reembed`. Typed `AiMemory`, `AiMemoryMatch`, `AiMemorySearchResult`.
- `client.collections`: `create`, `list`, `get`, `update`, `delete`, and `from(name)` → `ingest(AiDocumentSource.text/url/storage, wait: true)` (polls with `waitFor` until `ready`/`failed`, `TIMEOUT` on expiry), hybrid `search` (score, similarity, keyword match, `**` highlight, chunk + document), `listDocuments`, `getDocument`, `remove`, `stats`.
- `client.ai.threads`: `create`, `list`, `get`, `delete`, and `from(id)` → `get`, `update`, `delete`, `messages`, `append` (text, image URL or `AiThreadPart.storage` parts), `run` (a `Stream<ThreadRunEvent>`: `ThreadRunMessage`, `ThreadRunCitation`, `ThreadRunDelta`, `ThreadRunToolCall`, `ThreadRunToolResult`, then `ThreadRunDone` or `ThreadRunError`; cancelling the subscription closes the connection and stops the run) and `runOnce`. Run options: `memory` (true or a `type:id` subject), `collections`, `tools` (`AiThreadTool.memorySearch` / `collectionsSearch`), `maxContextTokens`, model settings.
- `client.ai.traces(...)` (service key): per-call model, tokens, latency, cost and status.
- `from(table)…semantic(column, query, k:, hybridColumn:, minSimilarity:)` keeps the builder's `eq`/`gt`/`inFilter`/`isFilter`… filters and `limit` (as `k`); `database.semantic(table, column, query, filters: [SemanticFilter(...)])` calls it directly. Returns `SemanticResponse` (rows with `_similarity` and `_score`, plus `model`).

### Changed — Database
- `textSearch(column, query, config:, type:)` is now chainable with the other filters instead of throwing `UnsupportedError` (`type`: `websearch` (default), `plain`, `phrase`). New chainable `nearest(column, vector, metric:, limit:)`. Queries that use either run as one parameterized SELECT through the SQL endpoint (identifiers checked and quoted, values bound; RLS applies); `count` is then the number of rows returned. `update()`/`delete()` and `semantic()` refuse builders that use them.

### Internal
- `chatStream` and thread runs share one dart:io SSE helper (same cancel-closes-socket behaviour).

## [1.7.0]

### Added — AI gateway
- `client.ai`: `chat`, `chatStream` (a `Stream<AiStreamEvent>`: text deltas, tool calls, done or error), `embed` (768-dim vectors) and `models`, through the project's own provider keys. Tool calling and image inputs (`AiContentPart.image` with a data URL). Cancelling the stream subscription closes the connection so the server stops generating.
- Billed AI requests are never retried by the retry interceptor (`extra: {'noRetry': true}`).

### Fixed — Database
- **`deleteMany` no longer deletes unrelated rows.** It sent the filter
  *values* as ids (`deleteMany('posts', filters: {'author_id': 12})` ran
  `DELETE … WHERE id = 12`). `delete`/`deleteMany` now delete the rows whose
  columns equal **all** filters, and `count` is the real number of rows deleted.
- **`updateMany` respects its filters** (it ignored them and matched on
  `values['id']`). `update`/`updateMany` update every row matching all filters
  and report the real row count.
- **`from(table)` works.** `execute()`, `insert()`, `update()` and `delete()`
  threw `UnsupportedError`. The builder now calls the API directly.
- **`select()` filters, ordering, paging and columns are honoured.** They were
  sent in PostgREST syntax the API ignores, so every call returned the first
  page of the whole table. Filters now go as `filter=column:operator:value`,
  ordering as `sortBy`/`sortOrder`, paging as `limit` or `from`/`to`; columns
  are projected client-side.
- **Unsupported query features throw instead of returning wrong rows.**
  `contains`, `containedBy`, `overlaps`, `range*`, `textSearch`, `or`, `and`,
  `isNotNull`, more than one `order`, aliased/embedded selects, and `inFilter`
  values containing `,` throw `UnsupportedError`/`ArgumentError` before any
  request. Filter values may contain `:` (timestamps, URLs). `update()`/`delete()` on the builder accept equality filters only and
  refuse to run without a filter.
- **`sql()` works.** It sent `parameters` (the API field is `params`, so every
  parameterised query got 400) and returned the response envelope as a single
  row. It now returns the rows, with `count` = rows affected. `vectorSearch()`
  works again as a result.
- **Concurrent `database.*` calls no longer hang or swap results.** Calls
  were multiplexed through one bloc and settled the first waiting caller.
  Each call now returns its own future.
- **`insertMany()` no longer hits the service-role-only bulk route** (401). It
  inserts one row per request (not atomic) and returns the inserted rows.
- **Upsert throws `UnsupportedError`** instead of silently doing a plain
  insert. `insert(upsert: true)`, `from().upsert()` and
  `from().insert([...])` used to drop all but the first row; a list now
  inserts every row.

### Fixed — Auth & sessions
- **`OrbitNestClient.create(anonKey:)` works without a `.env` asset.** It
  crashed with `NotInitializedError` from flutter_dotenv.
- **An offline cold start no longer logs the user out.** A refresh that fails
  because of the network, a timeout, 408/429 or 5xx keeps the stored session
  and is retried on the next request. Only a refresh the server rejects (4xx)
  clears it.
- **Ordinary 401s no longer fire `onSessionExpired`.** An anonymous caller's
  401, a 401/403 on a retried request, a transient refresh failure, and any
  401 from analytics are returned to the caller instead of signalling "session
  expired". `onSessionExpired` fires only when the server rejects the refresh
  token.
- **No more silent downgrade to the anon key.** A 401 "invalid signature" was
  replayed with the anon key and reported as success.
- **Analytics sends the `apikey` header** with every request, and its 401s no
  longer trigger refresh-token rotation or logout.
- **`resetPassword()` no longer throws after the password was reset.** It
  returns `{email, message}`; the user signs in with the new password.
- **`verifySmsOtp()` updates auth state** (`isAuthenticated`, `currentUser`,
  `onAuthStateChange`), like a password sign-in.
- **`getUser()` returns a `User`** (it cast a `Map` to `User`) and throws
  instead of hanging when no user is signed in.
- **`refreshSession()` throws instead of hanging** when the refresh fails.
- **Requests made while a token refresh is running wait for it** instead of
  going out with the anon key (RLS saw no user); a refresh that fails offline
  keeps sending the user token. The 401 refresh-and-retry now keeps byte
  downloads and uploads working, and reuses a token another call already
  refreshed. Realtime refreshes once and reconnects when the server rejects
  the socket's token (close 4001).

### Added
- `updateUser(currentPassword:)` — the API now requires the current password
  to change the email or password.
- **`auth.verifyEmailChange(code)`.** Changing the email with `updateUser(email:, currentPassword:)` now only sends a code to the new address; call this with that code to apply the change.
- `code` on `enrollMfaTotp`, `regenerateMfaRecoveryCodes` and `unenrollMfa`
  — the API requires a current TOTP/recovery code once MFA is active.
- `auth.deleteUser()` — deletes the signed-in user's account and clears the
  local session.
- `realtime.reconnect()`.

### Fixed — Realtime
- The socket carries the signed-in user's access token and reconnects on
  sign-in/sign-out, so RLS-scoped subscriptions see that user's rows.
- `unsubscribe()` removes the server subscriptions (it sent the bare channel
  name, which matched nothing). `untrack()` sends the gateway's
  `presence.untrack`, so it drops presence without leaving the channel.
- Reconnect backoff now grows while the server is down (it reset to ~1 s).
- Server `error` frames reach `channel.events` as `RealtimeErrorEvent`, and a
  channel's `events` stream only carries its own tables' changes.

### Fixed — Errors
- API error codes and structured fields reach callers. `OrbitNestException`
  (and `AuthException`/`DatabaseException`/`FunctionException`) has a new
  `body` with the parsed error JSON, e.g. `QUOTA_EXCEEDED`'s
  `quota`/`plan`/`limit`/`usage`. `FunctionException` now keeps the API's
  `code` and `message` (it reported `UNKNOWN_FUNCTION_ERROR`).
- **Storage throws `StorageException`.** Every `storage.from(bucket)` request
  method (`upload`, `download`, `list`, `remove`, `createBucket`) throws a
  `StorageException` (an `OrbitNestException`) with the API's `statusCode`,
  `code`, `message` and `body` — e.g. 402 `QUOTA_EXCEEDED`, 403, 404 — instead
  of a raw `DioException`. `download` errors are decoded too.
- 402/403/429 (`QUOTA_EXCEEDED`, `PLAN_REQUIRED`, `MFA_ENROLLMENT_REQUIRED`,
  `SMS_RATE_LIMITED`, `SHARED_EMAIL_RATE_LIMITED`, …) never refresh or end the
  session. A 429 that carries a `code` is not retried.

### Fixed — Other
- `crash()` sends `error_type`, `error_message` and `stack_trace`, so crashes
  group by type.
- `dispose()` flushes queued analytics and closes the session-expired stream.
- Uploads are not retried with an already-sent `FormData` body.
- NestJS validation errors (`message` as a list) no longer crash the error
  interceptor.
- `X-Client-Info` reports the real SDK version.

### Deprecated
- `orbitnest.jobs` (needs the Studio admin API, always 401 from an app) and
  `orbitnest.migrations` (the routes do not exist). Use Studio or the
  OrbitNest CLI. They will be removed.

## [1.6.3]

### Fixed
- **One failing edge function no longer fails every call running beside it.**
  `OrbitNestFunctions` multiplexes concurrent invocations onto a single bloc and
  resolves them from its state stream. The success path routed a result to the
  one pending operation registered for that function name, but the error path
  completed *every* pending operation with whichever function happened to fail.
  An app whose dashboard fans out `get-dashboard`, `get-groups`, `get-insights`
  and one function that had been deleted server-side therefore saw all four
  reported as broken — each carrying the deleted function's name — even though
  three of them returned 200. Failures now settle only their own caller.
  Regression test: `test/functions_error_routing_test.dart`.

## [1.6.2]

### Fixed
- **Users no longer logged out on every app restart after ~15 minutes.** The
  `/auth/refresh` route authenticates off the refresh token in the request body
  and needs no Bearer access token, but `AuthInterceptor` wasn't skipping it.
  On a cold start the stored access token is already expired (15-min TTL), so
  attaching it to the refresh POST made `onRequest` trigger a *proactive*
  refresh that re-entered the very in-flight refresh future the POST belonged
  to — a self-deadlock. The refresh never completed, the session was cleared,
  and the app dropped to the login screen. `/auth/refresh` is now treated as a
  token-less auth endpoint, so the cold-start refresh completes cleanly and an
  active user's session survives for the full refresh-token lifetime. Regression
  test: `test/refresh_endpoint_no_token_test.dart`.

## [1.6.1]

### Fixed
- **Session no longer lost on cold restart after a token refresh race.** The
  AuthBloc's session-refresh handler called `/auth/refresh` directly instead of
  through `TokenManager`'s de-duplicated refresh. Because the backend rotates
  refresh tokens single-use, a refresh that raced a concurrent
  interceptor/proactive refresh could *lose* the race, 401, and then clear the
  session — even though the winning refresh had just persisted a valid rotated
  token. All refresh paths now share one in-flight request, so the race is gone.
  (Most visible right after registration, whose onboarding fires a burst of
  parallel authenticated requests.)
- **Background user reconciliation could clobber a rotated refresh token.**
  `_reconcileStoredUserFromServer` wrote back a session snapshot captured *before*
  its `getUser()` call; if that call refreshed the token, the stale token
  overwrote the rotated one. It now re-reads the latest stored session before
  merging the fresh user.
- **`storeSession` no longer overwrites a valid refresh token with an empty one.**
  A partial payload lacking a refresh token would otherwise make the next cold
  start wipe the whole session; the existing refresh token is now preserved.

## [1.6.0]

### Fixed
- **MFA sign-in challenge is now surfaced.** When an account has a verified MFA
  factor, `signInWithPassword` previously threw `Sign in failed` and dropped the
  server's `challenge_token`, making it impossible to complete an MFA-gated login.
  It now returns `{ mfa_required: true, challenge_token, factors }` (no session) —
  pass `challenge_token` to `verifyMfa(challengeToken:, code:)` to finish signing in.
- **`verifyMfa` now updates auth state.** It previously stored the session token
  but left `isAuthenticated`/`currentUser`/`currentSession` and the
  `onAuthStateChange` stream unchanged, so apps couldn't tell the user had logged
  in. It now transitions to the authenticated state like a normal sign-in.

### Added
- `AuthResponse` now exposes `mfaRequired`, `challengeToken`, `mfaFactors`, and an
  `isMfaRequired` getter.
- New `AuthMfaRequiredState` for apps that drive auth via the BLoC stream directly.

## [1.5.1]

### Changed
- Widened dependency constraints to support the latest stable releases of `flutter_bloc` (9.x), `flutter_dotenv` (6.x), and `flutter_secure_storage` (10.x).
- Raised the `dio` lower bound to `^5.5.0` (required for `DioMediaType`).

### Removed
- Dropped deprecated `flutter_secure_storage` Android cipher options; data migrates automatically.

### Added
- Added an `example/` with a minimal usage sample.

## [1.5.0]

### Added
- **Storage client**: upload, download, list, remove, and `getPublicUrl` with image transforms.

## [1.4.0]

### Added
- **MFA recovery codes**: `verifyMfaEnrollment` now surfaces `recovery_codes`, plus a new `regenerateMfaRecoveryCodes` method.

## [1.3.0]

### Added
- **Multi-factor authentication (TOTP)**, **SMS OTP sign-in**, and **pgvector vector search**.

## [1.2.0]

### Added
- **Migrations client**: trigger server-side migration runs, read status, and display logs (the SDK never executes migrations itself).

## [1.1.0]

### Added
- **Analytics module** with batched event ingestion.

## [1.0.9] - 2026-02-23

### Added
- **Automatic Token Refresh**: Implemented automatic token refresh mechanism that triggers when tokens expire or are within 5 minutes of expiration
- **Error Recovery with Retry**: Added comprehensive retry logic with exponential backoff for network failures (408, 429, 500-504 errors)
- **Query Builder Integration**: Completed BLoC query builder integration with proper error handling

### Improved
- **Token Management**: Enhanced token manager with refresh callback support and automatic refresh detection
- **Network Resilience**: Added RetryInterceptor with configurable retry policies (aggressive, standard, conservative)
- **Authentication Flow**: Improved initialization flow to automatically attempt token refresh on expired tokens
- **Error Messages**: Better error messages for query builder usage

### Fixed
- Token refresh TODO implementation completed
- Query builder now provides clearer error messages when used incorrectly
- Automatic token refresh triggers on app initialization when needed

### Technical Details
- Added `RetryPolicy` class with configurable retry strategies
- Added `RetryInterceptor` for automatic request retry with exponential backoff
- Enhanced `TokenManager` with refresh callback mechanism
- Updated `AuthBloc` to register refresh callback and handle automatic token refresh
- Improved query builder error handling and documentation

## [1.0.8] - Previous Release
- Base implementation with auth, database, and edge functions support
