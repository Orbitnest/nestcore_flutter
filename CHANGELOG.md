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
