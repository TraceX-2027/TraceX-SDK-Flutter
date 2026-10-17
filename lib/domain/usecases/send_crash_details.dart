import 'package:tracex_flutter/domain/entities/crash.dart';
import 'package:tracex_flutter/domain/repositories/base_crash_repository.dart';

class SendCrashDetails {
  final BaseCrashRepository baseCrashRepository;

  SendCrashDetails({required this.baseCrashRepository});

  Future<void> execute(Crash crash) async {
    await baseCrashRepository.sendCrashDetails(crash);
  }
}
