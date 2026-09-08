import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:tracex/domain/entities/environment.dart';

class EnvironmentCollector {
  final DeviceInfoPlugin _deviceInfo;
  final Battery _battery;

  PackageInfo? _packageInfo;

  String _osName = 'Unknown';
  String _osVersion = 'Unknown';
  String _deviceModel = 'Unknown';
  bool _isPhysicalDevice = true;

  EnvironmentCollector({DeviceInfoPlugin? deviceInfo, Battery? battery})
    : _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
      _battery = battery ?? Battery();

  Future<void> initialize() async {
    await _collectAppInfo();
    await _collectDeviceInfo();
  }

  Future<void> _collectAppInfo() async {
    try {
      _packageInfo = await PackageInfo.fromPlatform();
    } catch (_) {
      _packageInfo = null;
    }
  }

  Future<void> _collectDeviceInfo() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;

        _osName = 'Android';
        _osVersion = info.version.release;
        _deviceModel = info.model;
        _isPhysicalDevice = info.isPhysicalDevice;
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;

        _osName = 'iOS';
        _osVersion = info.systemVersion;
        _deviceModel = info.utsname.machine;
        _isPhysicalDevice = info.isPhysicalDevice;
      } else {
        _osName = Platform.operatingSystem;
        _osVersion = Platform.operatingSystemVersion;
      }
    } catch (_) {}
  }

  Future<Environment> collect() async {
    int batteryLevel = -1;

    try {
      batteryLevel = await _battery.batteryLevel;
    } catch (_) {
      batteryLevel = -1;
    }

    return Environment(
      appVersion: _packageInfo == null
          ? 'Unknown'
          : '${_packageInfo!.version}+${_packageInfo!.buildNumber}',

      runtimeVersion: 'Dart ${Platform.version}',

      osName: _osName,

      osVersion: _osVersion,

      deviceModel: _deviceModel,

      isPhysicalDevice: _isPhysicalDevice,

      // TODO: implement RAM collector
      freeRamMb: 0,
      totalRamMb: 0,

      batteryLevel: batteryLevel,

      // TODO: calculate using RAM information
      isLowMemory: false,
    );
  }
}
