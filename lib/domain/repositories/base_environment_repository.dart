import 'package:tracex_flutter/domain/entities/environment.dart';

abstract class BaseEnvironmentRepository {
  Future<void> initialize();

  Future<Environment> getEnvironmentDetails();
}
