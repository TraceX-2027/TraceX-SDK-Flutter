import 'package:tracex_flutter/data/datasources/crash_remote_datasource.dart';
import 'package:tracex_flutter/data/models/crashes_model.dart';
import 'package:tracex_flutter/domain/entities/crash.dart';
import 'package:tracex_flutter/domain/repositories/base_crash_repository.dart';

class CrashRepository extends BaseCrashRepository {
  final BaseCrashRemoteDatasource baseCrashRemoteDatasources;

  CrashRepository({required this.baseCrashRemoteDatasources});

  @override
  Future<void> sendCrashDetails(Crash crash) async {
    final crashesModel = CrashesModel(
      projectKey: crash.projectKey,
      platform: crash.platform,
      language: crash.language,
      occurredAt: crash.occurredAt,
      exceptionType: crash.exceptionType,
      errorMessage: crash.errorMessage,
      stackTrace: crash.stackTrace,
      environment: crash.environment,
      breadcrumbs: crash.breadcrumbs,
      id: crash.id,
    );

    await baseCrashRemoteDatasources.sendCrashDetails(crashesModel);
  }

  @override
  Future<void> sendBatchCrashDetails(List<Crash> crashes) async {
    final crashesModels = crashes
        .map(
          (crash) => CrashesModel(
            projectKey: crash.projectKey,
            platform: crash.platform,
            language: crash.language,
            occurredAt: crash.occurredAt,
            exceptionType: crash.exceptionType,
            errorMessage: crash.errorMessage,
            stackTrace: crash.stackTrace,
            environment: crash.environment,
            breadcrumbs: crash.breadcrumbs,
            id: crash.id,
          ),
        )
        .toList();

    await baseCrashRemoteDatasources.sendBatchCrashDetails(crashesModels);
  }
}
