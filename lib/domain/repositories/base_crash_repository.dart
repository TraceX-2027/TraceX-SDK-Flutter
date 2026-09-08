import 'package:tracex/domain/entities/crash.dart';

abstract class BaseCrashRepository {
  Future<void> sentCrashDetils(Crash crash);
}
