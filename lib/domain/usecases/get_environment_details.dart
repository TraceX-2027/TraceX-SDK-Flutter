import 'package:tracex/domain/entities/environment.dart';
import 'package:tracex/domain/repositories/base_environment_repository.dart';

class GetEnvironmentDetails {
  final BaseEnvironmentRepository baseEnvironmentCollector;

  GetEnvironmentDetails({required this.baseEnvironmentCollector});
  Future<Environment> execute() async {
    return await baseEnvironmentCollector.getEnvironmentDetails();
  }

  Future<void> initialize() async {
    await baseEnvironmentCollector.initialize();
  }
}
