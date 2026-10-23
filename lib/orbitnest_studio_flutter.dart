library orbitnest_studio_flutter;

// Main client with direct method access (Supabase-style API)
export 'src/client/orbitnest_client.dart';

// Simplified APIs (available through main client or directly)
export 'src/auth/orbitnest_auth.dart';
export 'src/database/orbitnest_database.dart';
export 'src/edge_functions/orbitnest_functions.dart';

// Authentication models and exceptions
export 'src/auth/models/user.dart';
export 'src/auth/models/session.dart';
export 'src/auth/models/auth_response.dart';
export 'src/auth/models/passkey_device.dart';
export 'src/auth/exceptions/auth_exception.dart';
export 'src/auth/services/passkey_authenticator_service.dart';

// Database models and query builder
export 'src/database/models/postgrest_response.dart';
export 'src/database/models/semantic_response.dart';
export 'src/database/services/query_builder.dart';
export 'src/database/exceptions/database_exception.dart';

// Edge Functions models and exceptions
export 'src/edge_functions/models/function_response.dart';
export 'src/edge_functions/exceptions/function_exception.dart';

// Background Jobs models, service, and exceptions
export 'src/jobs/models/job_response.dart';
export 'src/jobs/services/jobs_service.dart';
export 'src/jobs/exceptions/job_exception.dart';

// Database Migrations — trigger server-side runs, read status, display logs
// (the Flutter SDK never executes migrations itself).
export 'src/migrations/models/migration_models.dart';
export 'src/migrations/services/migration_service.dart';
export 'src/migrations/exceptions/migration_exception.dart';
export 'src/migrations/migration_log_controller.dart';

// Realtime — live DB subscriptions, broadcasts, and presence
export 'src/realtime/orbitnest_realtime.dart';

// Storage — upload/download/list/remove + public URLs with image transforms
export 'src/storage/orbitnest_storage.dart';
export 'src/storage/exceptions/storage_exception.dart';

// AI Gateway — chat, streaming, tool calls and embeddings
export 'src/ai/orbitnest_ai.dart';
// AI data — memory, collections, threads, traces
export 'src/ai/ai_data.dart';
export 'src/ai/ai_data_models.dart';

// Types and utilities
export 'src/types/json_types.dart';
export 'src/types/response_types.dart';
export 'src/utils/env_config.dart';
export 'src/utils/logger.dart';
export 'src/constants/constants.dart';
export 'src/constants/error_codes.dart';

// Base exception
export 'src/client/interceptors/error_interceptor.dart' show OrbitNestException;

// ========================================
// BLoC exports (for advanced users only)
// ========================================
// Note: Most users should use the direct method API above.
// BLoCs are exported for users who want reactive state management.

// Authentication BLoC
export 'src/auth/bloc/auth_bloc.dart';
export 'src/auth/bloc/auth_event.dart';
export 'src/auth/bloc/auth_state.dart';

// Database BLoC
export 'src/database/bloc/database_bloc.dart';
export 'src/database/bloc/database_event.dart';
export 'src/database/bloc/database_state.dart';

// Edge Functions BLoC
export 'src/edge_functions/bloc/functions_bloc.dart';
export 'src/edge_functions/bloc/functions_event.dart';
export 'src/edge_functions/bloc/functions_state.dart';
