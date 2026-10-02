import 'package:tracex/domain/entities/crash.dart';
import 'package:tracex/domain/repositories/base_crash_offline_repository.dart';

class CrashOffline {
  final BaseCrashOfflineRepository baseCrashOfflineRepository;
  CrashOffline({required this.baseCrashOfflineRepository});
  Future<void> saveCrash(Crash crash) async {
    await baseCrashOfflineRepository.saveCrash(crash);
  }

  List<Crash> getCachedCrashes() {
    return baseCrashOfflineRepository.getCachedCrashes();
  }

  Future<void> deleteCrash(Crash crash) async {
    await baseCrashOfflineRepository.deleteCrash(crash);
  }

  Future<void> clear() async {
    await baseCrashOfflineRepository.clear();
  }
}
