// Pre-1.9.0 (OrbitNest) names, kept so existing apps compile after switching
// to nestcore_flutter. Each alias is the same type as its NestCore* target, so
// constructors, factories and static members work through it
// (e.g. `OrbitNestClient.create(...)`, `OrbitNestConstants.version`).
// They will be removed in a future major version.

import 'ai/ai_data.dart';
import 'ai/nestcore_ai.dart';
import 'auth/nestcore_auth.dart';
import 'client/interceptors/error_interceptor.dart';
import 'client/nestcore_client.dart';
import 'constants/constants.dart';
import 'database/nestcore_database.dart';
import 'edge_functions/nestcore_functions.dart';
import 'realtime/nestcore_realtime.dart';
import 'storage/nestcore_storage.dart';
import 'utils/logger.dart';

@Deprecated('Use NestCoreClient')
typedef OrbitNestClient = NestCoreClient;

@Deprecated('Use NestCoreAuth')
typedef OrbitNestAuth = NestCoreAuth;

@Deprecated('Use NestCoreDatabase')
typedef OrbitNestDatabase = NestCoreDatabase;

@Deprecated('Use NestCoreFunctions')
typedef OrbitNestFunctions = NestCoreFunctions;

@Deprecated('Use NestCoreRealtime')
typedef OrbitNestRealtime = NestCoreRealtime;

@Deprecated('Use NestCoreStorage')
typedef OrbitNestStorage = NestCoreStorage;

@Deprecated('Use NestCoreAi')
typedef OrbitNestAi = NestCoreAi;

@Deprecated('Use NestCoreMemory')
typedef OrbitNestMemory = NestCoreMemory;

@Deprecated('Use NestCoreCollections')
typedef OrbitNestCollections = NestCoreCollections;

@Deprecated('Use NestCoreException')
typedef OrbitNestException = NestCoreException;

@Deprecated('Use NestCoreConstants')
typedef OrbitNestConstants = NestCoreConstants;

@Deprecated('Use NestCoreLogger')
typedef OrbitNestLogger = NestCoreLogger;
