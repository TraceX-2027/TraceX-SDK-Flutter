import 'package:tracex/domain/entities/crash.dart';

abstract class BaseCrashOfflineRepository {
  Future<void> saveCrash(Crash crash);

  List<Crash> getCachedCrashes();

  Future<void> deleteCrash(Crash crash);

  Future<void> clear();
}
