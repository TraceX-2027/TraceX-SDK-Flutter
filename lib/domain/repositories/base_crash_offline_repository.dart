import 'package:tracex_flutter/domain/entities/crash.dart';

abstract class BaseCrashOfflineRepository {
  Future<void> saveCrash(Crash crash);

  List<Crash> getCachedCrashes();

  Future<void> deleteCrash(Crash crash);
  Future<void> deleteCrashesOffline(List<Crash> crashes);
}
