import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:tracex/data/models/crashes_model.dart';

abstract class BaseCrashRemoteDatasource {
  Future<void> sendCrashDetails(CrashesModel crash);
}

class CrashRemoteDatasource extends BaseCrashRemoteDatasource {
  final Dio dio;

  CrashRemoteDatasource({required this.dio});

  @override
  Future<void> sendCrashDetails(CrashesModel crash) async {
    final jsonData = jsonEncode(crash.toJson());

    final jsonBytes = utf8.encode(jsonData);
    if (jsonBytes.length > 5 * 1024) {
      final compressedData = gzip.encode(jsonBytes);

      await dio.post(
        '/crashes',
        options: Options(
          headers: {
            'X-TraceX-Key': crash.projectKey,
            'Content-Type': 'application/json',
            'Content-Encoding': 'gzip',
            'User-Agent': 'TraceX-Flutter-SDK/1.0.0',
          },
        ),
        data: compressedData,
      );

      return;
    }

    await dio.post(
      '/crashes',
      options: Options(
        headers: {
          'X-TraceX-Key': crash.projectKey,
          'Content-Type': 'application/json',
          'User-Agent': 'TraceX-Flutter-SDK/1.0.0',
        },
      ),
      data: jsonData,
    );

    debugPrint(crash.toJson().toString());
    debugPrint(crash.environment.freeRamMb.toString());
    debugPrint(crash.environment.totalRamMb.toString());
  }
}
