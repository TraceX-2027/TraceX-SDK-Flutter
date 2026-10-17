import 'package:tracex_flutter/domain/entities/crash.dart';

abstract class BaseCrashRepository {
  Future<void> sendCrashDetails(Crash crash);
  Future<void> sendBatchCrashDetails(List<Crash> crashes);
}
