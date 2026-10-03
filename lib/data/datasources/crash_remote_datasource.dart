import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:tracex/data/models/crashes_model.dart';

abstract class BaseCrashRemoteDatasource {
  Future<void> sendCrashDetails(CrashesModel crash);
}

class CrashRemoteDatasource extends BaseCrashRemoteDatasource {
  final Dio dio;
  final String? fallbackUrl;
  bool _preferFallback = false;

  CrashRemoteDatasource({
    required this.dio,
    this.fallbackUrl,
  });

  @visibleForTesting
  bool get isPreferringFallback => _preferFallback;

  @visibleForTesting
  set preferFallbackForTesting(bool value) => _preferFallback = value;

  @override
  Future<void> sendCrashDetails(CrashesModel crash) async {
    final Map<String, dynamic> preparedPayload;

    if (kIsWeb) {
      final jsonStr = jsonEncode(crash.toJson());
      preparedPayload = {'data': jsonStr, 'isGzip': false};
    } else {
      preparedPayload = await Isolate.run(() {
        final jsonStr = jsonEncode(crash.toJson());
        final bytes = utf8.encode(jsonStr);

        if (bytes.length > 5 * 1024) {
          return {
            'data': Uint8List.fromList(gzip.encode(bytes)),
            'isGzip': true,
          };
        }

        return {'data': jsonStr, 'isGzip': false};
      });
    }

    final isGzip = preparedPayload['isGzip'] as bool;
    final payloadData = preparedPayload['data'];

    final headers = {
      'X-TraceX-Key': crash.projectKey,
      'Content-Type': 'application/json',
      if (isGzip) 'Content-Encoding': 'gzip',
      'User-Agent': 'TraceX-Flutter-SDK/1.0.0',
    };

    if (_preferFallback && fallbackUrl != null) {
      await dio.post(
        fallbackUrl!,
        options: Options(
          headers: headers,
          connectTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
        data: payloadData,
      );
      return;
    }

    try {
      await dio.post(
        'crashes',
        options: Options(
          headers: headers,
          connectTimeout: fallbackUrl != null ? const Duration(milliseconds: 1500) : null,
          sendTimeout: fallbackUrl != null ? const Duration(seconds: 3) : null,
          receiveTimeout: fallbackUrl != null ? const Duration(seconds: 3) : null,
        ),
        data: payloadData,
      );
    } catch (e) {
      if (fallbackUrl != null && _isEligibleForFallback(e)) {
        _preferFallback = true;
        debugPrint(
          '[TraceX] Primary edge dispatch failed ($e). Falling back to origin: $fallbackUrl',
        );
        await dio.post(
          fallbackUrl!,
          options: Options(
            headers: headers,
            connectTimeout: const Duration(seconds: 5),
            sendTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ),
          data: payloadData,
        );
        return;
      }
      rethrow;
    }
  }

  bool _isEligibleForFallback(Object e) {
    if (e is DioException) {
      final statusCode = e.response?.statusCode;
      if (statusCode != null && statusCode >= 400 && statusCode < 500) {
        return false;
      }
      return true;
    }
    return true;
  }
}

