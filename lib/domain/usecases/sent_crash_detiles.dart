import 'package:tracex/domain/entities/crash.dart';
import 'package:tracex/domain/repositories/base_crash_repository.dart';

class SentCrashDetiles {
  final BaseCrashRepository baseCrashRepository;

  SentCrashDetiles({required this.baseCrashRepository});

  Future<void> execute(Crash crash) async {
    await baseCrashRepository.sentCrashDetils(crash);
  }
}
