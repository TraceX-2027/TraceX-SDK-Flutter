import 'package:tracex/data/datasorces/crash_remote_datasorces.dart';
import 'package:tracex/data/models/crashes_model.dart';
import 'package:tracex/domain/entities/crash.dart';
import 'package:tracex/domain/repositories/base_crash_repository.dart';

class CrashRepositoriy extends BaseCrashRepository {
  final BaseCrashRemoteDatasorces baseCrashRemoteDatasorces;

  CrashRepositoriy({required this.baseCrashRemoteDatasorces});

  @override
  Future<void> sentCrashDetils(Crash crash) async {
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

      await baseCrashRemoteDatasorces.sentCrashDetails(crashesModel);
    } catch (e) {
      throw Exception('Failed to send crash: $e');
    }
  }
}
