import 'package:tracex_flutter/domain/entities/crash.dart';
import 'package:tracex_flutter/domain/repositories/base_crash_repository.dart';

class SendBatchCrashDetails {
  final BaseCrashRepository baseCrashRepository;

  SendBatchCrashDetails({required this.baseCrashRepository});

  Future<void> execute(List<Crash> crashes) async {
    await baseCrashRepository.sendBatchCrashDetails(crashes);
  }
}
