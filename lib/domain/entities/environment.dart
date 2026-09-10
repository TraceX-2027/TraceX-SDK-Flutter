class Environment {
  final String appVersion;
  final String runtimeVersion;
  final String osName;
  final String osVersion;
  final String deviceModel;
  final bool isPhysicalDevice;
  final int freeRamMb;
  final int totalRamMb;
  final int batteryLevel;
  final bool isLowMemory;

  const Environment({
    required this.appVersion,
    required this.runtimeVersion,
    required this.osName,
    required this.osVersion,
    required this.deviceModel,
    required this.isPhysicalDevice,
    required this.freeRamMb,
    required this.totalRamMb,
    required this.batteryLevel,
    required this.isLowMemory,
  });
}
