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

  factory EnvironmentModel.fromEntity(Environment environment) {
    return EnvironmentModel(
      appVersion: environment.appVersion,
      runtimeVersion: environment.runtimeVersion,
      osName: environment.osName,
      osVersion: environment.osVersion,
      deviceModel: environment.deviceModel,
      isPhysicalDevice: environment.isPhysicalDevice,
      freeRamMb: environment.freeRamMb,
      totalRamMb: environment.totalRamMb,
      batteryLevel: environment.batteryLevel,
      isLowMemory: environment.isLowMemory,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'app_version': appVersion,
      'runtime_version': runtimeVersion,
      'os_name': osName,
      'os_version': osVersion,
      'device_model': deviceModel,
      'is_physical_device': isPhysicalDevice,
      'free_ram_mb': freeRamMb,
      'total_ram_mb': totalRamMb,
      'battery_level': batteryLevel,
      'is_low_memory': isLowMemory,
    };
  }
}
