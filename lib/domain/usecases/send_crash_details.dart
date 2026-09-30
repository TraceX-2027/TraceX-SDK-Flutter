import 'package:tracex/domain/entities/crash.dart';
import 'package:tracex/domain/repositories/base_crash_repository.dart';

class SendCrashDetails {
  final BaseCrashRepository baseCrashRepository;

  SendCrashDetails({required this.baseCrashRepository});

  Future<void> execute(Crash crash) async {
    await baseCrashRepository.sendCrashDetails(crash);
  }
}
