import 'package:tracex/domain/entities/environment.dart';

abstract class BaseEnvironmentRepository {
  Future<void> initialize();

  Future<Environment> getEnvironmentDetails();
}
