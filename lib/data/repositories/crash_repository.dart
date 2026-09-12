import 'package:tracex/data/datasources/crash_remote_datasource.dart';
import 'package:tracex/data/models/crashes_model.dart';
import 'package:tracex/domain/entities/crash.dart';
import 'package:tracex/domain/repositories/base_crash_repository.dart';

class CrashRepository extends BaseCrashRepository {
  final BaseCrashRemoteDatasources baseCrashRemoteDatasources;

  CrashRepository({required this.baseCrashRemoteDatasources});

  @override
  Future<void> sendCrashDetils(Crash crash) async {
    try {
      final crashesModel = CrashesModel(
        projectKey: crash.projectKey,
        platform: crash.platform,
        language: crash.language,
        timestamp: crash.timestamp,
        exceptionType: crash.exceptionType,
        errorMessage: crash.errorMessage,
        stackTrace: crash.stackTrace,
        environment: crash.environment,
        breadcrumbs: crash.breadcrumbs,
      );

      await baseCrashRemoteDatasources.sentCrashDetails(crashesModel);
    } catch (e) {
      throw Exception('Failed to send crash: $e');
    }
  }
}
