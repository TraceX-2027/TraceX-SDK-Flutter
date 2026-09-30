import 'package:tracex/data/datasources/crash_offline_datasource.dart';
import 'package:tracex/data/models/crash_hive_model.dart';
import 'package:tracex/domain/entities/crash.dart';
import 'package:tracex/domain/repositories/base_crash_offline_repository.dart';

class CrashOfflineRepository extends BaseCrashOfflineRepository {
  final BaseCrashOfflineDatasource datasource;
  CrashOfflineRepository({required this.datasource});
  @override
  Future<void> saveCrash(Crash crash) async {
    final hiveCrash = CrashHiveModel.fromEntity(crash);
    await datasource.saveCrash(hiveCrash);
  }

  @override
  List<Crash> getCachedCrashes() {
    return datasource
        .getCachedCrashes()
        .map((crash) => crash.toEntity())
        .toList();
  }

  @override
  Future<void> deleteCrash(Crash crash) async {
    final cachedCrashes = datasource.getCachedCrashes();
    for (final cachedCrash in cachedCrashes) {
      final entity = cachedCrash.toEntity();
      if (_isSameCrash(entity, crash)) {
        await datasource.deleteCrash(cachedCrash.key);
        return;
      }
    }
  }

  bool _isSameCrash(Crash first, Crash second) {
    return first.occurredAt.toUtc().toIso8601String() ==
            second.occurredAt.toUtc().toIso8601String() &&
        first.exceptionType == second.exceptionType &&
        first.errorMessage == second.errorMessage &&
        first.stackTrace == second.stackTrace;
  }

  @override
  Future<void> clear() async {
    await datasource.clear();
  }
}
