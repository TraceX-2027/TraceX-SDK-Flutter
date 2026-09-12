import 'package:tracex/domain/entities/crash.dart';
import 'package:tracex/domain/repositories/base_crash_repository.dart';

class SendCrashDetils {
  final BaseCrashRepository baseCrashRepository;

  SendCrashDetils({required this.baseCrashRepository});

  Future<void> execute(Crash crash) async {
    await baseCrashRepository.sendCrashDetils(crash);
  }
}
