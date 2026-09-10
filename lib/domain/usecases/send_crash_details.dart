import 'package:tracex/domain/entities/crash.dart';
import 'package:tracex/domain/repositories/base_crash_repository.dart';

class SentCrashDetils {
  final BaseCrashRepository baseCrashRepository;

  SentCrashDetils({required this.baseCrashRepository});

  Future<void> execute(Crash crash) async {
    await baseCrashRepository.sentCrashDetils(crash);
  }
}
