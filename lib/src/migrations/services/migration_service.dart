import '../../client/http_client.dart';
import '../../constants/endpoints.dart';
import '../models/migration_models.dart';
import '../exceptions/migration_exception.dart';

/// Client for the server-side migration runner.
///
/// The Flutter SDK **never executes migrations itself** — it only triggers a
/// run on the server and reads back status. Running migrations needs DDL
/// privileges and filesystem access to the migration files, which live on the
/// backend / a trusted runner, not in a mobile app.
class MigrationService {
  final NestCoreHttpClient _httpClient;
  final String _projectSlug;

  MigrationService({
    required NestCoreHttpClient httpClient,
    required String projectSlug,
  })  : _httpClient = httpClient,
        _projectSlug = projectSlug;

  static dynamic _unwrap(dynamic body) =>
      (body is Map && body['data'] != null) ? body['data'] : body;

  /// Trigger a migration run on the server. Pass [migrationId] to run a single
  /// migration; omit it to apply all pending migrations.
  Future<MigrationRunResult> run({String? migrationId}) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectMigrationsRun(_projectSlug),
        data: {
          if (migrationId != null) 'migrationId': migrationId,
        },
      );
      final data = _unwrap(response.data);
      return MigrationRunResult.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (e) {
      throw MigrationException.fromException(e);
    }
  }

  /// Fetch the status of every migration (applied / pending / failed).
  Future<List<MigrationStatusEntry>> status() async {
    try {
      final response = await _httpClient.get(
        Endpoints.projectMigrationsStatus(_projectSlug),
      );
      final data = _unwrap(response.data);

      final list = (data is Map && data['migrations'] is List)
          ? data['migrations'] as List
          : (data is List ? data : const []);

      return list
          .map((m) => MigrationStatusEntry.fromJson(Map<String, dynamic>.from(m as Map)))
          .toList();
    } catch (e) {
      throw MigrationException.fromException(e);
    }
  }
}
