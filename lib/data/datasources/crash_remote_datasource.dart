import 'dart:convert';
import 'dart:io';
import 'dart:isolate'; // 👈 استيراد مكتبة الـ Isolate

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
    final preparedPayload = await Isolate.run(() {
      final jsonStr = jsonEncode(crash.toJson());
      final bytes = utf8.encode(jsonStr);

      if (bytes.length > 5 * 1024) {
        return {'data': gzip.encode(bytes), 'isGzip': true};
      }

      return {'data': jsonStr, 'isGzip': false};
    });

    final isGzip = preparedPayload['isGzip'] as bool;
    final payloadData = preparedPayload['data'];

    await dio.post(
      'crashes',
      options: Options(
        headers: {
          'X-TraceX-Key': crash.projectKey,
          'Content-Type': 'application/json',
          if (isGzip) 'Content-Encoding': 'gzip',
          'User-Agent': 'TraceX-Flutter-SDK/1.0.0',
        },
      ),
      data: isGzip
          ? Stream.fromIterable([payloadData as List<int>])
          : payloadData,
    );

    debugPrint(crash.toJson().toString());
    debugPrint(crash.environment.freeRamMb.toString());
    debugPrint(crash.environment.totalRamMb.toString());
  }
}
