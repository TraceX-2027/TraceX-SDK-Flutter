import 'package:flutter/foundation.dart';
import 'package:tracex/data/collectors/environment_collector.dart';
import 'package:tracex/domain/entities/environment.dart';
import 'package:tracex/domain/repositories/base_environment_repository.dart';

class EnvironmentRepository extends BaseEnvironmentRepository {
  final EnvironmentCollector environmentCollector;

  EnvironmentRepository({required this.environmentCollector});

  @override
  Future<Environment> getEnvironmentDetails() async {
    try {
      return await environmentCollector.collect();
    } catch (e) {
      debugPrint('TraceX error: $e');
      rethrow;
    }
  }

  @override
  Future<void> initialize() async {
    try {
      await environmentCollector.initialize();
    } catch (e) {
      debugPrint('TraceX error: $e');
      rethrow;
    }
  }
}
