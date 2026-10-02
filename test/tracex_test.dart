import 'package:flutter_test/flutter_test.dart';
import 'package:tracex/core/services/crash_rate_limiter.dart';
import 'package:tracex/data/models/crashes_model.dart';
import 'package:tracex/domain/entities/breadcrumb.dart';
import 'package:tracex/domain/entities/environment.dart';

void main() {
  group('T1.17b: TraceX Crash Serialization & Core Logic Tests', () {
    test(
      'CrashesModel.toJson() should contain all required schema keys and occurred_at',
      () {
        final now = DateTime.now().toUtc();

        final crash = CrashesModel(
          projectKey: 'test-project-key-123',
          platform: 'flutter',
          language: 'dart',
          occurredAt: now,
          exceptionType: 'FormatException',
          errorMessage: 'Invalid format encountered',
          stackTrace: 'main.dart:42:10',
          environment: const Environment(
            appVersion: '1.0.0+1',
            runtimeVersion: 'Dart 3.9.2',
            osName: 'Android',
            osVersion: '13',
            deviceModel: 'Pixel 7',
            isPhysicalDevice: true,
            freeRamMb: 2048,
            totalRamMb: 8192,
            batteryLevel: 85,
            isLowMemory: false,
          ),
          breadcrumbs: [
            Breadcrumb(
              sequenceOrder: 1,
              timestamp: now,
              category: 'navigation',
              action: 'push',
              target: '/home',
              data: const {'route': '/home'},
            ),
          ],
        );

        final json = crash.toJson();

        // 1. فحص وجود جميع المفاتيح الأساسية
        expect(json.containsKey('project_key'), isTrue);
        expect(json['project_key'], equals('test-project-key-123'));
        expect(json['platform'], equals('flutter'));
        expect(json['language'], equals('dart'));
        expect(json['exception_type'], equals('FormatException'));
        expect(json['error_message'], equals('Invalid format encountered'));
        expect(json['stack_trace'], equals('main.dart:42:10'));

        // 2. التحقق الحاسم من مفتاح occurred_at وصيغة ISO 8601 UTC
        expect(json.containsKey('occurred_at'), isTrue);
        expect(json['occurred_at'], isA<String>());
        expect((json['occurred_at'] as String).endsWith('Z'), isTrue);
        expect(json['occurred_at'], equals(now.toIso8601String()));

        // 3. التحقق من مفاتيح الـ Environment
        expect(json.containsKey('environment'), isTrue);
        final env = json['environment'] as Map<String, dynamic>;
        expect(env['app_version'], equals('1.0.0+1'));
        expect(env['device_model'], equals('Pixel 7'));

        // 4. التحقق من أن الـ Breadcrumbs محتفظة بمفتاح timestamp
        expect(json.containsKey('breadcrumbs'), isTrue);
        final breadcrumbs = json['breadcrumbs'] as List;
        expect(breadcrumbs.length, equals(1));
        expect(breadcrumbs.first['timestamp'], equals(now.toIso8601String()));
        expect(breadcrumbs.first['category'], equals('navigation'));
      },
    );

    test(
      'CrashRateLimiter should limit rapid duplicate crashes up to 10 max',
      () {
        final rateLimiter = CrashRateLimiter();

        // أول 10 محاولات مسموح بها
        for (int i = 0; i < 10; i++) {
          expect(rateLimiter.allow(), isTrue);
        }

        // المحاولة الحادية عشرة يجب أن ترفض (Rate limit exceeded)
        expect(rateLimiter.allow(), isFalse);
      },
    );
  });
}
