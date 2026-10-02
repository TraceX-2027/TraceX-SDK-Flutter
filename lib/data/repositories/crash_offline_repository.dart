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
    if (crash.id != null) {
      await datasource.deleteCrash(crash.id);
      return;
    }
  }

  @override
  Future<void> clear() async {
    await datasource.clear();
  }
}
