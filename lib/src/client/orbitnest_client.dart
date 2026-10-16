import '../analytics/orbitnest_analytics.dart';
import '../analytics/services/analytics_service.dart';
import 'dart:async';
import '../auth/bloc/auth_bloc.dart';
import '../auth/bloc/auth_state.dart';
import '../auth/repositories/auth_repository.dart';
import '../auth/services/auth_service.dart';
import '../auth/services/token_manager.dart';
import '../auth/orbitnest_auth.dart';
import '../database/bloc/database_bloc.dart';
import '../database/repositories/database_repository.dart';
import '../database/services/database_service.dart';
import '../database/services/query_builder.dart';
import '../database/orbitnest_database.dart';
import '../edge_functions/bloc/functions_bloc.dart';
import '../edge_functions/repositories/functions_repository.dart';
import '../edge_functions/services/functions_service.dart';
import '../edge_functions/orbitnest_functions.dart';
import '../ai/orbitnest_ai.dart';
import '../jobs/services/jobs_service.dart';
import '../migrations/services/migration_service.dart';
import '../realtime/orbitnest_realtime.dart';
import '../storage/orbitnest_storage.dart';
import '../utils/env_config.dart';
import 'http_client.dart';

/// Main client for OrbitNest Studio
class OrbitNestClient {
  late final String _baseUrl;
  late final String _projectSlug;
  late final String _anonKey;
  late final OrbitNestHttpClient _httpClient;
  late final TokenManager _tokenManager;

  // Services
  late final AuthService _authService;
  late final DatabaseService _databaseService;
  late final FunctionsService _functionsService;
  late final JobsService _jobsService;
  late final MigrationService _migrationService;
  late final AnalyticsService _analyticsService;

  // Repositories
  late final AuthRepository _authRepository;
  late final DatabaseRepository _databaseRepository;
  late final FunctionsRepository _functionsRepository;

  // BLoCs (internal)
  late final AuthBloc _authBloc;
  late final DatabaseBloc _databaseBloc;
  late final FunctionsBloc _functionsBloc;

  // Simplified API wrappers
  late final OrbitNestAuth _auth;
  late final OrbitNestDatabase _database;
  late final OrbitNestFunctions _functions;
  late final OrbitNestRealtime _realtime;
  late final OrbitNestAnalytics _analytics;
  late final OrbitNestStorage _storage;
  late final OrbitNestAi _ai;
  late final StreamSubscription<AuthState> _authSubscription;

  OrbitNestClient._({
    required String baseUrl,
    required String projectSlug,
    required String anonKey,
  })  : _baseUrl = baseUrl,
        _projectSlug = projectSlug,
        _anonKey = anonKey {
    _initialize();
  }

  /// Create a new OrbitNest client using environment configuration.
  ///
  /// Only [anonKey] is required (read from `ORBITNEST_ANON_KEY` in `.env`).
  /// The base URL is hardcoded to `https://api.orbitnest.io` and the project
  /// slug is automatically decoded from the anon key JWT payload — no other
  /// env vars are needed.
  ///
  /// SECURITY: this is a client SDK. Only the public, RLS-protected anon key
  /// belongs in a mobile app. The service-role key is a server-side admin
  /// credential and must NEVER be bundled into a shipped app — it is not
  /// accepted here by design.
  factory OrbitNestClient.create({
    String? anonKey,
  }) {
    if (!EnvConfig.isInitialized) {
      throw Exception(
        'EnvConfig not initialized. Call EnvConfig.initialize() before creating OrbitNestClient.',
      );
    }

    final resolvedAnonKey = anonKey ?? EnvConfig.anonKey;
    final resolvedSlug = EnvConfig.decodeProjectSlugFromJwt(resolvedAnonKey);

    return OrbitNestClient._(
      baseUrl: EnvConfig.baseUrl,
      projectSlug: resolvedSlug,
      anonKey: resolvedAnonKey,
    );
  }

  void _initialize() {
    // Initialize token manager
    _tokenManager = TokenManager(
      projectSlug: _projectSlug,
      apiKey: _anonKey,
    );
    // Persist anonKey to secure storage so getApiKey()'s storage-fallback path
    // also returns it (e.g. if TokenManager is ever reconstructed without apiKey).
    _tokenManager.storeApiKey(_anonKey).ignore();

    // Initialize HTTP client
    _httpClient = OrbitNestHttpClient(
      baseUrl: _baseUrl,
      tokenManager: _tokenManager,
    );

    // Initialize services
    _authService = AuthService(
      httpClient: _httpClient,
      projectSlug: _projectSlug,
    );

    _databaseService = DatabaseService(
      httpClient: _httpClient,
      projectSlug: _projectSlug,
    );

    _functionsService = FunctionsService(
      httpClient: _httpClient,
      projectSlug: _projectSlug,
    );

    _jobsService = JobsService(
      httpClient: _httpClient,
      projectSlug: _projectSlug,
    );

    _migrationService = MigrationService(
      httpClient: _httpClient,
      projectSlug: _projectSlug,
    );

    _analyticsService = AnalyticsService(
      httpClient: _httpClient,
      baseUrl: _baseUrl,
    );
    _analytics = OrbitNestAnalytics(_analyticsService);

    // Initialize repositories
    _authRepository = AuthRepository(authService: _authService);
    _databaseRepository = DatabaseRepository(databaseService: _databaseService);
    _functionsRepository =
        FunctionsRepository(functionsService: _functionsService);

    // Initialize BLoCs
    _authBloc = AuthBloc(
      authRepository: _authRepository,
      tokenManager: _tokenManager,
    );

    _databaseBloc = DatabaseBloc(databaseRepository: _databaseRepository);
    _functionsBloc = FunctionsBloc(functionsRepository: _functionsRepository);

    // Initialize simplified API wrappers
    _auth = OrbitNestAuth(_authBloc, _authService, _tokenManager);
    _database = OrbitNestDatabase(_databaseBloc, _databaseService);
    _functions = OrbitNestFunctions(_functionsBloc);
    _realtime = OrbitNestRealtime(
      baseUrl: _baseUrl,
      projectSlug: _projectSlug,
      apiKey: _anonKey,
      // Read on every (re)connect so the socket carries the current user.
      accessTokenProvider: _tokenManager.getAccessToken,
      // The server refused the socket's token: refresh, then reconnect with it.
      onAuthRejected: () async {
        if (await _tokenManager.refreshSession()) await _realtime.reconnect();
      },
    );
    // Reconnect realtime when the signed-in user changes so RLS-scoped
    // subscriptions follow sign-in / sign-out.
    String? lastUserId;
    _authSubscription = _authBloc.stream.listen((state) {
      final String? userId;
      if (state is AuthAuthenticatedState) {
        userId = state.user.id;
      } else if (state is AuthUnauthenticatedState) {
        userId = null;
      } else {
        return;
      }
      if (userId != lastUserId) {
        lastUserId = userId;
        _realtime.reconnect();
      }
    });
    _storage = OrbitNestStorage(
      httpClient: _httpClient,
      baseUrl: _baseUrl,
      projectSlug: _projectSlug,
    );
    _ai = OrbitNestAi(httpClient: _httpClient, projectSlug: _projectSlug);
  }

  /// Get the authentication API (simplified interface)
  OrbitNestAuth get auth => _auth;

  /// Get the database API (simplified interface)
  OrbitNestDatabase get database => _database;

  /// Get the functions API (simplified interface)
  OrbitNestFunctions get functions => _functions;

  /// Get the realtime API — create live subscriptions and broadcasts.
  ///
  /// ```dart
  /// final ch = client.realtime.channel('orders')
  ///   ..onPostgresChanges(
  ///       event: PgEvent.insert,
  ///       table: 'orders',
  ///       callback: (e) => print(e.newRow))
  ///   ..subscribe();
  /// ```
  OrbitNestRealtime get realtime => _realtime;

  /// Get the storage API — `client.storage.from('bucket').upload(...)`,
  /// `download`, `list`, `remove`, and `getPublicUrl` (with image transforms).
  OrbitNestStorage get storage => _storage;

  /// AI Gateway — `client.ai.chat(...)`, `chatStream(...)`, `embed(...)`,
  /// `models()` with the project's own provider keys.
  OrbitNestAi get ai => _ai;

  /// Convenience shortcut: create a realtime channel directly on the client.
  RealtimeChannel channel(String name) => _realtime.channel(name);

  /// Background jobs live behind the Studio admin API (admin JWT + project
  /// UUID); an app's anon key or user token always gets 401 here.
  @Deprecated('Not callable from a client app — every call returns 401. '
      'Trigger jobs from Studio, the CLI or a server. Will be removed.')
  JobsService get jobs => _jobsService;

  /// The migration routes this calls do not exist on the API (404).
  @Deprecated('No such API route — every call fails with 404. Run migrations '
      'with the OrbitNest CLI or Studio. Will be removed.')
  MigrationService get migrations => _migrationService;

  /// Get the analytics API — track events, screens, crashes, and user identity.
  OrbitNestAnalytics get analytics => _analytics;

  /// Stream that emits whenever the server has decisively rejected the
  /// current session — e.g. a 401 on a data/edge-function call that even a
  /// token refresh could not recover from. Host apps should listen here and
  /// force the user to the sign-in flow when it fires.
  ///
  /// ```dart
  /// client.onSessionExpired.listen((_) => authBloc.add(ForceLogout()));
  /// ```
  Stream<void> get onSessionExpired => _tokenManager.onSessionExpired;

  // ============================
  // Direct Function Methods (Supabase-style API)
  // ============================

  /// Invoke an edge function directly
  /// Usage: orbitnest.function('my-function', params: {...})
  Future<dynamic> function(
    String functionName, {
    dynamic params,
    String method = 'POST',
    Map<String, String>? headers,
  }) async {
    final response = await _functions.invoke(
      functionName,
      method: method,
      body: params,
      headers: headers,
    );
    return response.data;
  }

  // ============================
  // Direct Database Methods (Supabase-style API)
  // ============================

  /// Select data from a table
  /// Usage: orbitnest.select('users', filters: {'status': 'active'})
  Future<List<Map<String, dynamic>>> select(
    String table, {
    String columns = '*',
    Map<String, dynamic>? filters,
    List<String>? orderBy,
    int? limit,
    int? offset,
  }) async {
    final response = await _database.select(
      table,
      columns: columns,
      filters: filters,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    return response.data;
  }

  /// Insert data into a table
  /// Usage: orbitnest.insert('users', {'name': 'John', 'email': 'john@example.com'})
  Future<List<Map<String, dynamic>>> insert(
    String table,
    Map<String, dynamic> values, {
    bool upsert = false,
  }) async {
    final response = await _database.insert(table, values, upsert: upsert);
    return response.data;
  }

  /// Update data in a table
  /// Usage: orbitnest.update('users', {'name': 'Jane'}, filters: {'id': 1})
  Future<List<Map<String, dynamic>>> update(
    String table,
    Map<String, dynamic> values, {
    required Map<String, dynamic> filters,
  }) async {
    final response = await _database.update(table, values, filters: filters);
    return response.data;
  }

  /// Delete data from a table
  /// Usage: orbitnest.delete('users', filters: {'id': 1})
  Future<List<Map<String, dynamic>>> delete(
    String table, {
    required Map<String, dynamic> filters,
  }) async {
    final response = await _database.delete(table, filters: filters);
    return response.data;
  }

  /// Execute raw SQL query
  /// Usage: orbitnest.sql(r'SELECT * FROM users WHERE status = $1', parameters: ['active'])
  Future<List<Map<String, dynamic>>> sql(
    String query, {
    List<dynamic>? parameters,
  }) async {
    final response = await _database.sql(query, parameters: parameters);
    return response.data;
  }

  // ============================
  // Direct Authentication Methods (Supabase-style API)
  // ============================

  /// Sign in with email and password
  /// Usage: orbitnest.signIn('user@example.com', 'password')
  Future<Map<String, dynamic>> signIn(String email, String password) async {
    return await _auth.signInWithPassword(email: email, password: password);
  }

  /// Sign up with email and password
  /// Optionally pass [metadata] (e.g. display_name) to store in user_metadata.
  /// Usage: orbitnest.signUp('user@example.com', 'password', metadata: {'display_name': 'Alice'})
  Future<Map<String, dynamic>> signUp(
    String email,
    String password, {
    Map<String, dynamic>? metadata,
  }) async {
    return await _auth.signUp(email: email, password: password, metadata: metadata);
  }

  /// Sign out the current user
  /// Usage: orbitnest.signOut()
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Get the current user
  /// Usage: orbitnest.currentUser()
  Map<String, dynamic>? currentUser() {
    final user = _auth.currentUser;
    return user?.toJson();
  }

  /// Get the current session
  /// Usage: orbitnest.currentSession()
  Map<String, dynamic>? currentSession() {
    final session = _auth.currentSession;
    return session?.toJson();
  }

  /// Supabase-compatible query builder for database operations
  PostgrestQueryBuilder<Map<String, dynamic>> from(String table) {
    return _database.from(table);
  }

  /// Get the project slug
  String get projectSlug => _projectSlug;

  /// Get the base URL
  String get baseUrl => _baseUrl;

  /// Get the anonymous key
  String get anonKey => _anonKey;

  /// Close the client and clean up resources
  void dispose() {
    _auth.dispose();
    _database.dispose();
    _functions.dispose();
    _realtime.dispose();
    _authSubscription.cancel();
    _authBloc.close();
    _databaseBloc.close();
    _functionsBloc.close();
    _tokenManager.dispose();
    // Flush queued analytics first; the HTTP client closes once that is done.
    _analyticsService.dispose().whenComplete(_httpClient.close);
  }
}
