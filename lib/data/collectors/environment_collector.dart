import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tracex_flutter/domain/entities/environment.dart';

class EnvironmentCollector {
  static const MethodChannel _channel = MethodChannel('tracex/environment');

  String _osName = 'Unknown';
  String _osVersion = 'Unknown';
  String _deviceModel = 'Unknown';
  String _appVersion = 'Unknown';
  bool _isPhysicalDevice = false;

  // ----------------------------------------------------------
  // Initialize (Static info collected once at startup)
  // ----------------------------------------------------------

  Future<void> initialize() async {
    if (kIsWeb) {
      _osName = 'Web';
      _osVersion = 'Web';
      _deviceModel = 'Browser';
      _appVersion = '1.0.0';
      _isPhysicalDevice = false;
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'getEnvironmentInfo',
        );

        if (result != null) {
          _osName = defaultTargetPlatform == TargetPlatform.android
              ? 'Android'
              : 'iOS';
          _osVersion = result['osVersion']?.toString() ?? 'Unknown';
          _deviceModel = result['deviceModel']?.toString() ?? 'Unknown';
          _appVersion = result['appVersion']?.toString() ?? 'Unknown';
          _isPhysicalDevice = result['isPhysicalDevice'] as bool? ?? false;
          return;
        }
      } catch (e) {
        debugPrint(
          'TraceX: Failed to initialize environment info via native: $e',
        );
      }
    }

    _osName = defaultTargetPlatform.name;
    _osVersion = 'Unknown';
    _deviceModel = 'Unknown';
    _isPhysicalDevice = false;
  }

  // ----------------------------------------------------------
  // Collect Dynamic Environment (Real-time dynamic data on crash)
  // ----------------------------------------------------------

  Future<Environment> collect() async {
    if (kIsWeb) {
      return Environment(
        appVersion: _appVersion,
        runtimeVersion: 'Dart Web',
        osName: _osName,
        osVersion: _osVersion,
        deviceModel: _deviceModel,
        isPhysicalDevice: _isPhysicalDevice,
        freeRamMb: 0,
        totalRamMb: 0,
        batteryLevel: -1,
        isLowMemory: false,
      );
    }

    int freeRamMb = 0;
    int totalRamMb = 0;
    int batteryLevel = -1;
    bool isLowMemory = false;

    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'getEnvironmentInfo',
        );

        if (result != null) {
          totalRamMb = (result['totalRamMb'] as num?)?.toInt() ?? 0;
          freeRamMb = (result['freeRamMb'] as num?)?.toInt() ?? 0;
          isLowMemory = result['isLowMemory'] as bool? ?? false;
          batteryLevel = (result['batteryLevel'] as num?)?.toInt() ?? -1;

          if (result['appVersion'] != null) {
            _appVersion = result['appVersion'].toString();
          }
          if (result['deviceModel'] != null) {
            _deviceModel = result['deviceModel'].toString();
          }
          if (result['osVersion'] != null) {
            _osVersion = result['osVersion'].toString();
          }
        }
      } catch (e) {
        debugPrint('TraceX: Failed to collect real-time environment info: $e');
      }
    }

    return Environment(
      appVersion: _appVersion,
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
}
