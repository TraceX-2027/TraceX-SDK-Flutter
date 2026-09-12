import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:tracex/core/utils/api_const.dart';
import 'package:tracex/data/models/crashes_model.dart';

abstract class BaseCrashRemoteDatasources {
  Future<void> sentCrashDetails(CrashesModel crash);
}

class CrashRemoteDatasource extends BaseCrashRemoteDatasources {
  final Dio dio;

  CrashRemoteDatasource({required this.dio});
  @override
  Future<void> sentCrashDetails(CrashesModel crash) async {
    try {
      await dio.post(
        ApiConst.crashUrl,

        options: Options(
          headers: {
            'X-TraceX-Key': crash.projectKey,
            'Content-Type': 'application/json',
          },
        ),

        data: crash.toJson(),
      );

      debugPrint(crash.toJson().toString());
      debugPrint(crash.environment.freeRamMb.toString());
      debugPrint(crash.environment.totalRamMb.toString());
    } on DioException catch (e) {
      throw Exception('Failed to send crash: ${e.message}');
    }
  }
}
