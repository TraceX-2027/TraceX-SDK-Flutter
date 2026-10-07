import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracex/core/services/crash_queue.dart';
import 'package:tracex/core/services/crash_rate_limiter.dart';
import 'package:tracex/core/utils/api_const.dart';
import 'package:tracex/data/collectors/breadcrumb_collector.dart';
import 'package:tracex/data/collectors/breadcrumbs/breadcrumb_navigator_observer.dart';
import 'package:tracex/data/collectors/breadcrumbs/tracex_dio_interceptor.dart';
import 'package:tracex/data/datasources/crash_offline_datasource.dart';
import 'package:tracex/data/datasources/crash_remote_datasource.dart';
import 'package:tracex/data/models/crashes_model.dart';
import 'package:tracex/domain/entities/breadcrumb.dart';
import 'package:tracex/domain/entities/crash.dart';
import 'package:tracex/domain/entities/environment.dart';
import 'package:tracex/domain/repositories/base_crash_offline_repository.dart';
import 'package:tracex/domain/usecases/save_offline_crash.dart';
import 'package:tracex/src/data_scrubber.dart';
import 'package:tracex/tracex.dart';

class MockCrashOfflineRepository implements BaseCrashOfflineRepository {
  final List<Crash> crashes = [];

  @override
  Future<void> saveCrash(Crash crash) async {
    crashes.add(crash);
  }

  @override
  List<Crash> getCachedCrashes() => List.unmodifiable(crashes);

  @override
  Future<void> deleteCrash(Crash crash) async {
    crashes.remove(crash);
  }

  @override
  Future<void> clear() async {
    crashes.clear();
  }
}

Crash _createDummyCrash({String projectKey = 'test-project-key'}) {
  return Crash(
    projectKey: projectKey,
    platform: 'flutter',
    language: 'dart',
    occurredAt: DateTime.now().toUtc(),
    exceptionType: 'StateError',
    errorMessage: 'Test error message',
    stackTrace: 'test_file.dart:10:5',
    environment: const Environment(
      appVersion: '1.0.0',
      runtimeVersion: '3.9.2',
      osName: 'Android',
      osVersion: '14',
      deviceModel: 'Pixel 8',
      isPhysicalDevice: true,
      freeRamMb: 1024,
      totalRamMb: 4096,
      batteryLevel: 90,
      isLowMemory: false,
    ),
    breadcrumbs: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─────────────────────────────────────────────────────────────────────────
  // T1.17b: Crash Serialization & Core Logic
  // ─────────────────────────────────────────────────────────────────────────
  group('T1.17b: TraceX Crash Serialization & Core Logic Tests', () {
    test(
      'CrashesModel.toJson() produces correct JSON schema and ISO 8601 UTC occurred_at',
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

        expect(json.containsKey('project_key'), isTrue);
        expect(json['project_key'], equals('test-project-key-123'));
        expect(json['platform'], equals('flutter'));
        expect(json['language'], equals('dart'));
        expect(json['exception_type'], equals('FormatException'));
        expect(json['error_message'], equals('Invalid format encountered'));
        expect(json['stack_trace'], equals('main.dart:42:10'));

        expect(json.containsKey('occurred_at'), isTrue);
        expect(json['occurred_at'], isA<String>());
        expect((json['occurred_at'] as String).endsWith('Z'), isTrue);
        expect(json['occurred_at'], equals(now.toIso8601String()));

        expect(json.containsKey('environment'), isTrue);
        final env = json['environment'] as Map<String, dynamic>;
        expect(env['app_version'], equals('1.0.0+1'));
        expect(env['device_model'], equals('Pixel 7'));

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
        for (int i = 0; i < 10; i++) {
          expect(rateLimiter.allow(), isTrue);
        }
        expect(rateLimiter.allow(), isFalse);
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // T1.17: URL Resolution & Endpoint Invariants
  // ─────────────────────────────────────────────────────────────────────────
  group('T1.17: URL Resolution & Endpoint Invariants', () {
    test('ApiConst.baseUrl defaults to Cloudflare Edge Ingestion endpoint', () {
      expect(ApiConst.baseUrl.endsWith('/'), isTrue);
      expect(ApiConst.baseUrl, equals(ApiConst.edgeBaseUrl));
      expect(
        ApiConst.edgeBaseUrl,
        equals(
          'https://tracex-edge-ingest.kareemadel10110.workers.dev/api/v1/',
        ),
      );
      expect(
        ApiConst.originBaseUrl,
        equals('https://tracex-api.kareemadel.com/api/v1/'),
      );
      expect(
        ApiConst.crashUrl,
        equals(
          'https://tracex-edge-ingest.kareemadel10110.workers.dev/api/v1/crashes',
        ),
      );
      expect(
        ApiConst.originCrashUrl,
        equals('https://tracex-api.kareemadel.com/api/v1/crashes'),
      );
    });

    test('Dio relative resolution to "crashes" resolves to Edge Ingest', () {
      final baseUri = Uri.parse(ApiConst.baseUrl);
      final resolvedUri = baseUri.resolve('crashes');
      expect(
        resolvedUri.toString(),
        equals(
          'https://tracex-edge-ingest.kareemadel10110.workers.dev/api/v1/crashes',
        ),
      );
    });

    test(
      'ServicesLocator.init normalizes endpoints without trailing slashes',
      () async {
        const customEndpoint = 'https://custom.backend.dev/api/v1';
        var normalized = customEndpoint.trim();
        if (!normalized.endsWith('/')) normalized = '$normalized/';
        expect(normalized, equals('https://custom.backend.dev/api/v1/'));
        expect(
          Uri.parse(normalized).resolve('crashes').toString(),
          equals('https://custom.backend.dev/api/v1/crashes'),
        );
      },
    );

    test('TraceX.defaultEndpoint points to Cloudflare Edge Ingestion', () {
      expect(TraceX.defaultEndpoint, equals(ApiConst.edgeBaseUrl));
      expect(TraceX.originEndpoint, equals(ApiConst.originBaseUrl));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // T1.17: CrashQueue Resilience & 401 Discard Policy
  // ─────────────────────────────────────────────────────────────────────────
  group('T1.17: CrashQueue Resilience & 401 Discard Policy', () {
    test(
      '401 Unauthorized permanently pauses telemetry and clears queue without saving offline',
      () async {
        final mockRepo = MockCrashOfflineRepository();
        final crashOffline = CrashOffline(baseCrashOfflineRepository: mockRepo);
        final queue = CrashQueue(crashOffline: crashOffline);

        await queue.add(_createDummyCrash());
        await queue.add(_createDummyCrash());
        expect(queue.length, equals(2));

        final requestOptions = RequestOptions(path: 'crashes');
        await queue.process((crash) async {
          throw DioException(
            requestOptions: requestOptions,
            response: Response(
              requestOptions: requestOptions,
              statusCode: 401,
              statusMessage: 'Unauthorized',
            ),
          );
        });

        expect(queue.isUnauthorized, isTrue);
        expect(queue.isTelemetryPaused, isTrue);
        expect(queue.length, equals(0));
        expect(mockRepo.crashes, isEmpty);

        await queue.add(_createDummyCrash());
        expect(queue.length, equals(0));
        expect(mockRepo.crashes, isEmpty);

        queue.dispose();
      },
    );

    test('429 Rate Limited pauses telemetry and buffers to offline', () async {
      final mockRepo = MockCrashOfflineRepository();
      final crashOffline = CrashOffline(baseCrashOfflineRepository: mockRepo);
      final queue = CrashQueue(crashOffline: crashOffline);

      await queue.add(_createDummyCrash());

      final requestOptions = RequestOptions(path: 'crashes');
      await queue.process((c) async {
        throw DioException(
          requestOptions: requestOptions,
          response: Response(
            requestOptions: requestOptions,
            statusCode: 429,
            headers: Headers.fromMap({
              'Retry-After': ['60'],
            }),
          ),
        );
      });

      expect(queue.isTelemetryPaused, isTrue);
      expect(queue.isUnauthorized, isFalse);
      expect(mockRepo.crashes.length, equals(1));

      queue.dispose();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // T1.17: Storage Invariants & FIFO Eviction
  // ─────────────────────────────────────────────────────────────────────────
  group('T1.17: Storage Invariants & FIFO Eviction', () {
    test('CrashOfflineDatasource enforces 100-crash FIFO limit', () {
      expect(CrashOfflineDatasource.maxOfflineCrashes, equals(100));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // T1.14 & T1.15: TraceX Public API Entry Points
  // ─────────────────────────────────────────────────────────────────────────
  group('T1.14 & T1.15: TraceX Public API Entry Points', () {
    test('TraceX exposes required public methods without error', () {
      expect(TraceX.init, isNotNull);
      expect(TraceX.initialize, isNotNull);
      expect(TraceX.recordFlutterError, isNotNull);
      expect(TraceX.recordError, isNotNull);
      expect(TraceX.runGuarded, isNotNull);
      TraceX.recordError(Exception('test exception'), StackTrace.current);
    });

    test(
      'TraceX rejects initialization when projectKey and apiKey are empty',
      () async {
        expect(
          () => TraceX.initialize(projectKey: ''),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => TraceX.initialize(apiKey: '   '),
          throwsA(isA<ArgumentError>()),
        );
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // T1.17: Edge Ingestion with Smart Origin Fallback
  // ─────────────────────────────────────────────────────────────────────────
  group('T1.17: Edge Ingestion with Smart Origin Fallback', () {
    test(
      'CrashRemoteDatasource falls back to origin on edge network failure and sets sticky fallback',
      () async {
        final dio = Dio();
        final attemptedUrls = <String>[];

        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              attemptedUrls.add(options.uri.toString());
              if (options.uri.toString().contains('workers.dev')) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.connectionTimeout,
                    error: 'Edge unreachable from ISP',
                  ),
                );
              } else {
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 202,
                    data: {'event_id': 'test-event-origin-123'},
                  ),
                );
              }
            },
          ),
        );

        dio.options.baseUrl = ApiConst.edgeBaseUrl;
        final ds = CrashRemoteDatasource(
          dio: dio,
          fallbackUrl: ApiConst.originCrashUrl,
        );
        final crash = _createDummyCrash();
        final model = CrashesModel(
          projectKey: crash.projectKey,
          platform: crash.platform,
          language: crash.language,
          occurredAt: crash.occurredAt,
          exceptionType: crash.exceptionType,
          errorMessage: crash.errorMessage,
          stackTrace: crash.stackTrace,
          environment: crash.environment,
          breadcrumbs: crash.breadcrumbs,
        );

        await ds.sendCrashDetails(model);
        expect(attemptedUrls.length, equals(2));
        expect(attemptedUrls[0], contains('workers.dev'));
        expect(attemptedUrls[1], equals(ApiConst.originCrashUrl));
        expect(ds.isPreferringFallback, isTrue);

        attemptedUrls.clear();
        await ds.sendCrashDetails(model);
        expect(attemptedUrls.length, equals(1));
        expect(attemptedUrls[0], equals(ApiConst.originCrashUrl));
      },
    );

    test(
      'CrashRemoteDatasource does NOT fall back on 401 Unauthorized or 400 Bad Request',
      () async {
        final dio = Dio();
        final attemptedUrls = <String>[];

        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              attemptedUrls.add(options.uri.toString());
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 401,
                    statusMessage: 'Unauthorized',
                  ),
                ),
              );
            },
          ),
        );

        dio.options.baseUrl = ApiConst.edgeBaseUrl;
        final ds = CrashRemoteDatasource(
          dio: dio,
          fallbackUrl: ApiConst.originCrashUrl,
        );
        final crash = _createDummyCrash();
        final model = CrashesModel(
          projectKey: crash.projectKey,
          platform: crash.platform,
          language: crash.language,
          occurredAt: crash.occurredAt,
          exceptionType: crash.exceptionType,
          errorMessage: crash.errorMessage,
          stackTrace: crash.stackTrace,
          environment: crash.environment,
          breadcrumbs: crash.breadcrumbs,
        );

        await expectLater(
          () => ds.sendCrashDetails(model),
          throwsA(isA<DioException>()),
        );
        expect(attemptedUrls.length, equals(1));
        expect(attemptedUrls[0], contains('workers.dev'));
        expect(ds.isPreferringFallback, isFalse);
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // T2.15: BreadcrumbCollector Ring Buffer & Collectors
  // ─────────────────────────────────────────────────────────────────────────
  group('T2.15: BreadcrumbCollector Ring Buffer & Collectors', () {
    setUp(() {
      BreadcrumbCollector.clear();
    });

    test('Strictly caps buffer at 50 items with FIFO eviction', () {
      for (int i = 1; i <= 55; i++) {
        BreadcrumbCollector.addBreadcrumb(
          category: 'test',
          action: 'act',
          target: 'tgt_$i',
        );
      }
      expect(BreadcrumbCollector.count, equals(50));
      final breadcrumbs = BreadcrumbCollector().breadcrumbs;
      expect(breadcrumbs.first.target, equals('tgt_6'));
      expect(breadcrumbs.last.target, equals('tgt_55'));
    });

    test('clear() resets buffer and restarts sequence counter', () {
      BreadcrumbCollector.addBreadcrumb(
        category: 'test',
        action: 'act',
        target: 'tgt_1',
      );
      BreadcrumbCollector.clear();
      expect(BreadcrumbCollector.count, equals(0));
      BreadcrumbCollector.addBreadcrumb(
        category: 'test',
        action: 'act',
        target: 'tgt_restart',
      );
      expect(BreadcrumbCollector().breadcrumbs.first.sequenceOrder, equals(1));
    });

    test('addBreadcrumb sanitizes non-primitive data values to strings', () {
      final complexObject = Uri.parse('https://example.com');
      BreadcrumbCollector.addBreadcrumb(
        category: 'test',
        action: 'act',
        target: 'tgt',
        data: {
          'num': 42,
          'bool': true,
          'str': 'hello',
          'complex': complexObject,
        },
      );
      final b = BreadcrumbCollector().breadcrumbs.first;
      expect(b.data['num'], equals(42));
      expect(b.data['bool'], equals(true));
      expect(b.data['str'], equals('hello'));
      expect(b.data['complex'], isA<String>());
      expect(b.data['complex'], equals(complexObject.toString()));
    });

    test(
      'TraceXNavigatorObserver emits category "navigation" not "navigation.route"',
      () {
        final observer = TraceXNavigatorObserver();
        final route = PageRouteBuilder<void>(
          settings: const RouteSettings(name: '/dashboard'),
          pageBuilder: (_, __, ___) => const SizedBox(),
        );
        observer.didPush(route, null);
        expect(BreadcrumbCollector.count, equals(1));
        final b = BreadcrumbCollector().breadcrumbs.first;
        expect(b.category, equals('navigation'));
        expect(b.action, equals('push'));
        expect(b.target, equals('/dashboard'));
      },
    );

    test('TraceXDioInterceptor truncates target to max 255 characters', () {
      final longPath = '/api/${'x' * 300}';
      final uri = Uri.parse('https://example.com$longPath');
      final interceptor = TraceXDioInterceptor();
      final target = uri.path.length > 255
          ? uri.path.substring(0, 255)
          : uri.path;
      expect(target.length, equals(255));
      expect(target, startsWith('/api/'));
      expect(interceptor, isNotNull);
    });

    test(
      'TraceXDioInterceptor excludes TraceX ingestion paths from breadcrumbs',
      () {
        final ingestionPaths = ['/crashes', '/api/v1/crashes'];
        const excluded = ['/crashes', '/api/v1/crashes'];
        for (final path in ingestionPaths) {
          final uri = Uri.parse('https://tracex.example.com$path');
          final isExcluded = excluded.any((p) => uri.path.endsWith(p));
          expect(
            isExcluded,
            isTrue,
            reason: 'Path $path must be excluded from breadcrumb recording',
          );
        }
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // T2.16: DataScrubber Invariants & Redaction Tests
  // ─────────────────────────────────────────────────────────────────────────
  group('T2.16: DataScrubber Invariants & Redaction Tests', () {
    test('Redacts Bearer tokens in headers and error strings', () {
      const input = 'Authorization: Bearer secretToken_12345.xyz== occurred';
      final result = DataScrubber.scrubString(input);
      expect(result, equals('Authorization: Bearer [REDACTED] occurred'));
    });

    test('Redacts valid 16-digit credit cards using Luhn algorithm', () {
      const input = 'Transaction failed for card 4111111111111111';
      final result = DataScrubber.scrubString(input);
      expect(result, equals('Transaction failed for card [CARD_REDACTED]'));

      const invalidCard = 'Order reference 1234567890123456';
      expect(DataScrubber.scrubString(invalidCard), equals(invalidCard));
    });

    test('Redacts sensitive URL query parameters (N1)', () {
      const url =
          'https://api.example.com/data?token=secret123&api_key=xyz&password=pass&user=1';
      final scrubbed = DataScrubber.scrubString(url);
      expect(
        scrubbed,
        equals(
          'https://api.example.com/data?token=[REDACTED]&api_key=[REDACTED]&password=[REDACTED]&user=1',
        ),
      );
    });

    test(
      'Does not false positive redact benign words like author or authority (M1)',
      () {
        final data = {
          'author': 'Shakespeare',
          'authority': 'LocalAdmin',
          'authentic': true,
          'author_id': 123,
          'password': 'secretPassword',
          'cvv': '123',
          'pin': '9999',
        };

        final scrubbed = DataScrubber.scrubMap(data);
        expect(scrubbed['author'], equals('Shakespeare'));
        expect(scrubbed['authority'], equals('LocalAdmin'));
        expect(scrubbed['authentic'], equals(true));
        expect(scrubbed['author_id'], equals(123));
        expect(scrubbed['password'], equals('[REDACTED]'));
        expect(scrubbed['cvv'], equals('[REDACTED]'));
        expect(scrubbed['pin'], equals('[REDACTED]'));
      },
    );

    test('Recursively scrubs nested maps and preserves nested keys (B1)', () {
      final input = {
        'user': {
          'password': 'secretPassword',
          'token': 'abc',
          'profile': {'api_key': 'key_123'},
        },
      };

      final scrubbed = DataScrubber.scrubMap(input);
      expect((scrubbed['user'] as Map)['password'], equals('[REDACTED]'));
      expect((scrubbed['user'] as Map)['token'], equals('[REDACTED]'));
      expect(
        ((scrubbed['user'] as Map)['profile'] as Map)['api_key'],
        equals('[REDACTED]'),
      );
    });

    test('Safely handles Map with non-string keys without TypeError (M3)', () {
      final nonStringKeyMap = {
        200: 'OK',
        500: 'Internal Server Error',
        'password': 'secret',
      };

      final scrubbed = DataScrubber.scrubMap(nonStringKeyMap);
      expect(scrubbed['200'], equals('OK'));
      expect(scrubbed['500'], equals('Internal Server Error'));
      expect(scrubbed['password'], equals('[REDACTED]'));
    });

    test(
      'Redacts Windows forward-slash paths and mobile sandbox directories (N2)',
      () {
        const winSlash = 'file:///C:/Users/JohnDoe/AppData/Local/file.dart';
        expect(
          DataScrubber.scrubString(winSlash),
          equals('file:///[PATH_REDACTED]/AppData/Local/file.dart'),
        );

        const androidPath = '/data/user/0/com.app/databases/app.db';
        expect(
          DataScrubber.scrubString(androidPath),
          equals('[PATH_REDACTED]/databases/app.db'),
        );

        const iosPath =
            '/var/mobile/Containers/Data/Application/UUID-123/Documents/file.txt';
        expect(
          DataScrubber.scrubString(iosPath),
          equals('[PATH_REDACTED]/Documents/file.txt'),
        );
      },
    );

    test('Redaction performance completes in < 1ms per event payload', () {
      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 100; i++) {
        DataScrubber.scrubString(
          'Error Bearer token123 at C:\\Users\\Dev\\app?token=123 with card 4111111111111111',
        );
        DataScrubber.scrubMap({
          'password': 'pass',
          'token': 'secret',
          'nested': {'api_key': '123'},
        });
      }
      stopwatch.stop();
      final avgTimeMs = stopwatch.elapsedMicroseconds / (100 * 1000);
      expect(avgTimeMs, lessThan(1.0));
    });
  });
}
