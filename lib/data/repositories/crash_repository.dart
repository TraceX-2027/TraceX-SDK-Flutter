import 'package:tracex/data/datasources/crash_remote_datasource.dart';
import 'package:tracex/data/models/crashes_model.dart';
import 'package:tracex/domain/entities/crash.dart';
import 'package:tracex/domain/repositories/base_crash_repository.dart';

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
    );

    await baseCrashRemoteDatasources.sendCrashDetails(crashesModel);
  }
}
