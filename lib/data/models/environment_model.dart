import 'package:tracex/domain/entities/environment.dart';

class EnvironmentModel extends Environment {
  EnvironmentModel({
    required super.appVersion,
    required super.runtimeVersion,
    required super.osName,
    required super.osVersion,
    required super.deviceModel,
    required super.isPhysicalDevice,
    required super.freeRamMb,
    required super.totalRamMb,
    required super.batteryLevel,
    required super.isLowMemory,
  });
}
