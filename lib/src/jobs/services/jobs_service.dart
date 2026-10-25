import '../../client/http_client.dart';
import '../../constants/endpoints.dart';
import '../models/job_response.dart';
import '../exceptions/job_exception.dart';

/// Service for background jobs API calls (admin only).
class JobsService {
  final NestCoreHttpClient _httpClient;
  final String _projectSlug;

  JobsService({
    required NestCoreHttpClient httpClient,
    required String projectSlug,
  })  : _httpClient = httpClient,
        _projectSlug = projectSlug;

  /// Create a new background job.
  Future<BackgroundJob> create({
    required String name,
    String? description,
    required String sourceCode,
    required String schedule,
    String timezone = 'UTC',
    Map<String, dynamic>? executionConfig,
  }) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectJobs(_projectSlug),
        data: {
          'name': name,
          if (description != null) 'description': description,
          'sourceCode': sourceCode,
          'schedule': schedule,
          'timezone': timezone,
          if (executionConfig != null) 'executionConfig': executionConfig,
        },
      );

      final data = response.data is Map && response.data['data'] != null
          ? response.data['data']
          : response.data;
      return BackgroundJob.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      throw JobException.fromException(e);
    }
  }

  /// List all background jobs for the current project.
  Future<List<BackgroundJob>> list() async {
    try {
      final response = await _httpClient.get(
        Endpoints.projectJobs(_projectSlug),
      );

      final data = response.data is Map && response.data['data'] != null
          ? response.data['data']
          : response.data;

      if (data is Map && data['jobs'] is List) {
        return (data['jobs'] as List)
            .map((j) => BackgroundJob.fromJson(Map<String, dynamic>.from(j)))
            .toList();
      }
      if (data is List) {
        return data
            .map((j) => BackgroundJob.fromJson(Map<String, dynamic>.from(j)))
            .toList();
      }
      return [];
    } catch (e) {
      throw JobException.fromException(e);
    }
  }

  /// Get a single background job by name.
  Future<BackgroundJob> get(String name) async {
    try {
      final response = await _httpClient.get(
        Endpoints.projectJobByName(_projectSlug, name),
      );

      final data = response.data is Map && response.data['data'] != null
          ? response.data['data']
          : response.data;
      return BackgroundJob.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      throw JobException.fromException(e);
    }
  }

  /// Update a background job.
  Future<BackgroundJob> update({
    required String name,
    String? description,
    String? sourceCode,
    String? status,
    String? schedule,
    String? timezone,
    Map<String, dynamic>? executionConfig,
  }) async {
    try {
      final response = await _httpClient.put(
        Endpoints.projectJobByName(_projectSlug, name),
        data: {
          if (description != null) 'description': description,
          if (sourceCode != null) 'sourceCode': sourceCode,
          if (status != null) 'status': status,
          if (schedule != null) 'schedule': schedule,
          if (timezone != null) 'timezone': timezone,
          if (executionConfig != null) 'executionConfig': executionConfig,
        },
      );

      final data = response.data is Map && response.data['data'] != null
          ? response.data['data']
          : response.data;
      return BackgroundJob.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      throw JobException.fromException(e);
    }
  }

  /// Delete a background job.
  Future<void> delete(String name) async {
    try {
      await _httpClient.delete(
        Endpoints.projectJobByName(_projectSlug, name),
      );
    } catch (e) {
      throw JobException.fromException(e);
    }
  }

  /// Manually trigger a background job.
  Future<BackgroundJobRun> trigger(String name) async {
    try {
      final response = await _httpClient.post(
        Endpoints.projectJobTrigger(_projectSlug, name),
      );

      final data = response.data is Map && response.data['data'] != null
          ? response.data['data']
          : response.data;
      return BackgroundJobRun.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      throw JobException.fromException(e);
    }
  }

  /// Get execution history for a background job.
  Future<List<BackgroundJobRun>> getRuns(
    String name, {
    int? limit,
  }) async {
    try {
      final response = await _httpClient.get(
        Endpoints.projectJobRuns(_projectSlug, name),
        queryParameters: {
          if (limit != null) 'limit': limit,
        },
      );

      final data = response.data is Map && response.data['data'] != null
          ? response.data['data']
          : response.data;

      if (data is Map && data['runs'] is List) {
        return (data['runs'] as List)
            .map((r) => BackgroundJobRun.fromJson(Map<String, dynamic>.from(r)))
            .toList();
      }
      if (data is List) {
        return data
            .map((r) => BackgroundJobRun.fromJson(Map<String, dynamic>.from(r)))
            .toList();
      }
      return [];
    } catch (e) {
      throw JobException.fromException(e);
    }
  }
}
