import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tracex/domain/entities/environment.dart';

class EnvironmentCollector {
  static const MethodChannel _channel = MethodChannel('tracex/environment');

  final DeviceInfoPlugin _deviceInfo;
  final Battery _battery;

  PackageInfo? _packageInfo;

  String _osName = 'Unknown';
  String _osVersion = 'Unknown';
  String _deviceModel = 'Unknown';
  bool _isPhysicalDevice = false;

  EnvironmentCollector({DeviceInfoPlugin? deviceInfo, Battery? battery})
    : _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
      _battery = battery ?? Battery();

  // ----------------------------------------------------------
  // Initialize
  // ----------------------------------------------------------

  Future<void> initialize() async {
    await _collectAppInfo();
    await _collectDeviceInfo();
  }

  // ----------------------------------------------------------
  // App Info
  // ----------------------------------------------------------

  Future<void> _collectAppInfo() async {
    try {
      _packageInfo = await PackageInfo.fromPlatform();
    } catch (e) {
      debugPrint('TraceX: Failed to collect app info: $e');
      _packageInfo = null;
    }
  }

  // ----------------------------------------------------------
  // Device Info (Static info collected once at startup)
  // ----------------------------------------------------------

  Future<void> _collectDeviceInfo() async {
    try {
      // --------------------------------------------------------
      // Web
      // --------------------------------------------------------

      if (kIsWeb) {
        final info = await _deviceInfo.webBrowserInfo;

        _osName = 'Web';
        _osVersion = info.userAgent ?? 'Unknown';
        _deviceModel = info.browserName.name;
        _isPhysicalDevice = false;
        return;
      }

      // --------------------------------------------------------
      // Android
      // --------------------------------------------------------

      if (defaultTargetPlatform == TargetPlatform.android) {
        final info = await _deviceInfo.androidInfo;

        _osName = 'Android';
        _osVersion = info.version.release;
        _deviceModel = info.model;
        _isPhysicalDevice = info.isPhysicalDevice;
        return;
      }

      // --------------------------------------------------------
      // iOS
      // --------------------------------------------------------

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final info = await _deviceInfo.iosInfo;

        _osName = 'iOS';
        _osVersion = info.systemVersion;
        _deviceModel = info.utsname.machine;
        _isPhysicalDevice = info.isPhysicalDevice;
        return;
      }

      // --------------------------------------------------------
      // Other Platforms
      // --------------------------------------------------------

      _osName = defaultTargetPlatform.name;
      _osVersion = 'Unknown';
      _deviceModel = 'Unknown';
      _isPhysicalDevice = false;
    } catch (e) {
      debugPrint('TraceX: Failed to collect device info: $e');
    }
  }

  // ----------------------------------------------------------
  // Memory Info
  // ----------------------------------------------------------

  Future<Map<String, dynamic>> _getMemoryInfo() async {
    if (kIsWeb) {
      return {'totalRamMb': 0, 'freeRamMb': 0, 'isLowMemory': false};
    }

    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'getMemoryInfo',
        );

        return {
          'totalRamMb': (result?['totalRamMb'] as num?)?.toInt() ?? 0,
          'freeRamMb': (result?['freeRamMb'] as num?)?.toInt() ?? 0,
          'isLowMemory': result?['isLowMemory'] as bool? ?? false,
        };
      } on PlatformException catch (e) {
        debugPrint('TraceX: Memory channel error ${e.code}: ${e.message}');
      } catch (e) {
        debugPrint('TraceX: Failed to get memory info: $e');
      }
    }

    return {'totalRamMb': 0, 'freeRamMb': 0, 'isLowMemory': false};
  }

  // ----------------------------------------------------------
  // Collect Environment (Real-time dynamic data on crash)
  // ----------------------------------------------------------

  // ----------------------------------------------------------
  // Collect Environment (Real-time dynamic data on crash)
  // ----------------------------------------------------------

  Future<Environment> collect() async {
    final results = await Future.wait([
      _getSafeBatteryLevel(),
      _getMemoryInfo(),
    ]);

    final batteryLevel = results[0] as int;
    final memory = results[1] as Map<String, dynamic>;

    final totalRamMb = (memory['totalRamMb'] as num?)?.toInt() ?? 0;
    final freeRamMb = (memory['freeRamMb'] as num?)?.toInt() ?? 0;
    final isLowMemory = memory['isLowMemory'] as bool? ?? false;

    return Environment(
      appVersion: _packageInfo == null
          ? 'Unknown'
          : '${_packageInfo!.version}+${_packageInfo!.buildNumber}',
      runtimeVersion: kIsWeb ? 'Dart Web' : 'Dart ${Platform.version}',
      osName: _osName,
      osVersion: _osVersion,
      deviceModel: _deviceModel,
      isPhysicalDevice: _isPhysicalDevice,
      freeRamMb: freeRamMb,
      totalRamMb: totalRamMb,
      batteryLevel: batteryLevel,
      isLowMemory: isLowMemory,
    );
  }

  Future<int> _getSafeBatteryLevel() async {
    try {
      return await _battery.batteryLevel;
    } catch (e) {
      debugPrint('TraceX: Failed to get battery level: $e');
      return -1;
    }
  }
}
