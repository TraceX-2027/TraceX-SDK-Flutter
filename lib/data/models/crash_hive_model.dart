import 'package:hive/hive.dart';
import 'package:tracex/domain/entities/breadcrumb.dart';
import 'package:tracex/domain/entities/crash.dart';
import 'package:tracex/domain/entities/environment.dart';

part 'crash_hive_model.g.dart';

@HiveType(typeId: 0)
class CrashHiveModel extends HiveObject {
  @HiveField(0)
  final String projectKey;

  @HiveField(1)
  final String platform;

  @HiveField(2)
  final String language;

  @HiveField(3)
  final DateTime occurredAt;

  @HiveField(4)
  final String exceptionType;

  @HiveField(5)
  final String errorMessage;

  @HiveField(6)
  final String stackTrace;

  @HiveField(7)
  final Map<String, dynamic> environment;

  @HiveField(8)
  final List<Map<String, dynamic>> breadcrumbs;

  CrashHiveModel({
    required this.projectKey,
    required this.platform,
    required this.language,
    required this.occurredAt,
    required this.exceptionType,
    required this.errorMessage,
    required this.stackTrace,
    required this.environment,
    required this.breadcrumbs,
  });

  factory CrashHiveModel.fromEntity(Crash crash) {
    return CrashHiveModel(
      projectKey: crash.projectKey,
      platform: crash.platform,
      language: crash.language,
      occurredAt: crash.occurredAt,
      exceptionType: crash.exceptionType,
      errorMessage: crash.errorMessage,
      stackTrace: crash.stackTrace,
      environment: {
        'app_version': crash.environment.appVersion,
        'runtime_version': crash.environment.runtimeVersion,
        'os_name': crash.environment.osName,
        'os_version': crash.environment.osVersion,
        'device_model': crash.environment.deviceModel,
        'is_physical_device': crash.environment.isPhysicalDevice,
        'free_ram_mb': crash.environment.freeRamMb,
        'total_ram_mb': crash.environment.totalRamMb,
        'battery_level': crash.environment.batteryLevel,
        'is_low_memory': crash.environment.isLowMemory,
      },
      breadcrumbs: crash.breadcrumbs.map((breadcrumb) {
        return {
          'sequence_order': breadcrumb.sequenceOrder,
          'timestamp': breadcrumb.timestamp.toUtc().toIso8601String(),
          'category': breadcrumb.category,
          'action': breadcrumb.action,
          'target': breadcrumb.target,
          'data': breadcrumb.data,
        };
      }).toList(),
    );
  }

  Crash toEntity() {
    return Crash(
      projectKey: projectKey,
      platform: platform,
      language: language,
      occurredAt: occurredAt,
      exceptionType: exceptionType,
      errorMessage: errorMessage,
      stackTrace: stackTrace,
      environment: Environment(
        appVersion: environment['app_version'],
        runtimeVersion: environment['runtime_version'],
        osName: environment['os_name'],
        osVersion: environment['os_version'],
        deviceModel: environment['device_model'],
        isPhysicalDevice: environment['is_physical_device'],
        freeRamMb: environment['free_ram_mb'],
        totalRamMb: environment['total_ram_mb'],
        batteryLevel: environment['battery_level'],
        isLowMemory: environment['is_low_memory'],
      ),
      breadcrumbs: breadcrumbs.map((breadcrumb) {
        return Breadcrumb(
          sequenceOrder: breadcrumb['sequence_order'] as int? ?? 0,
          timestamp:
              DateTime.tryParse(breadcrumb['timestamp']?.toString() ?? '') ??
              DateTime.now().toUtc(),
          category: breadcrumb['category']?.toString() ?? 'unknown',
          action: breadcrumb['action']?.toString() ?? 'unknown',
          target: breadcrumb['target']?.toString() ?? 'unknown',
          data:
              (breadcrumb['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
      }).toList(),
    );
  }
}
