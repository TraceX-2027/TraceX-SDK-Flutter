import 'dart:io';

import 'package:flutter/services.dart';

class IOSDeviceInfoCollector {
  static const MethodChannel _channel = MethodChannel('tracex/device_info');

  static Future<Map<String, dynamic>> getMemoryInfo() async {
    if (!Platform.isIOS) {
      return {'freeRamMb': 0, 'totalRamMb': 0, 'isLowMemory': false};
    }

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getMemoryInfo',
      );

      return {
        'freeRamMb': (result?['freeRamMb'] as num?)?.toInt() ?? 0,

        'totalRamMb': (result?['totalRamMb'] as num?)?.toInt() ?? 0,

        'isLowMemory': result?['isLowMemory'] as bool? ?? false,
      };
    } on PlatformException {
      return {'freeRamMb': 0, 'totalRamMb': 0, 'isLowMemory': false};
    } catch (e) {
      return {'freeRamMb': 0, 'totalRamMb': 0, 'isLowMemory': false};
    }
  }

  static Future<int> getBatteryLevel() async {
    if (!Platform.isIOS) {
      return -1;
    }

    try {
      final result = await _channel.invokeMethod<int>('getBatteryLevel');

      return result ?? -1;
    } catch (e) {
      return -1;
    }
  }

  static Future<Map<String, dynamic>> getDeviceInfo() async {
    final memoryInfo = await getMemoryInfo();

    return {
      'freeRamMb': memoryInfo['freeRamMb'],
      'totalRamMb': memoryInfo['totalRamMb'],
      'isLowMemory': memoryInfo['isLowMemory'],
    };
  }
}
