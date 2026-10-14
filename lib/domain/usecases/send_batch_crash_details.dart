import 'package:tracex/domain/entities/crash.dart';
import 'package:tracex/domain/repositories/base_crash_repository.dart';

class SendBatchCrashDetails {
  final BaseCrashRepository baseCrashRepository;

  SendBatchCrashDetails({required this.baseCrashRepository});

  Future<void> execute(List<Crash> crashes) async {
    await baseCrashRepository.sendBatchCrashDetails(crashes);
  }
}
