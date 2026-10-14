import 'package:tracex/domain/entities/crash.dart';

abstract class BaseCrashRepository {
  Future<void> sendCrashDetails(Crash crash);
  Future<void> sendBatchCrashDetails(List<Crash> crashes);
}
