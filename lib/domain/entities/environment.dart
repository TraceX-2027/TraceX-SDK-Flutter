/// Hardware, operating system, and runtime snapshot captured at the time of an incident.
class Environment {
  /// Application semantic version (e.g., '1.0.0').
  final String appVersion;

  /// Runtime or Dart VM version.
  final String runtimeVersion;

  /// Operating system name (e.g., 'Android', 'iOS', 'Web').
  final String osName;

  /// Operating system release or kernel version.
  final String osVersion;

  /// Manufacturer device model identifier.
  final String deviceModel;

  /// Whether the execution environment is a physical device or an emulator/simulator.
  final bool isPhysicalDevice;

  /// Approximate available free RAM in megabytes.
  final int freeRamMb;

  /// Total physical RAM installed on the device in megabytes.
  final int totalRamMb;

  /// Battery charge percentage (0-100).
  final int batteryLevel;

  /// Whether the operating system flagged a low memory warning condition.
  final bool isLowMemory;

  /// Creates an immutable [Environment] telemetry snapshot.
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
