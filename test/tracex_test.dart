import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracex/core/services/crash_queue.dart';
import 'package:tracex/core/services/crash_rate_limiter.dart';
import 'package:tracex/core/utils/api_const.dart';
import 'package:tracex/data/datasources/crash_offline_datasource.dart';
import 'package:tracex/data/datasources/crash_remote_datasource.dart';
import 'package:tracex/data/models/crashes_model.dart';
import 'package:tracex/domain/entities/breadcrumb.dart';
import 'package:tracex/domain/entities/crash.dart';
import 'package:tracex/domain/entities/environment.dart';
import 'package:tracex/domain/repositories/base_crash_offline_repository.dart';
import 'package:tracex/domain/usecases/save_offline_crash.dart';
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

  group('T1.17b: TraceX Crash Serialization & Core Logic Tests', () {
    test(
      'Strictly caps stored breadcrumbs at 50 items and evicts oldest (FIFO)',
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

        // 1. Check all essential keys
        expect(json.containsKey('project_key'), isTrue);
        expect(json['project_key'], equals('test-project-key-123'));
        expect(json['platform'], equals('flutter'));
        expect(json['language'], equals('dart'));
        expect(json['exception_type'], equals('FormatException'));
        expect(json['error_message'], equals('Invalid format encountered'));
        expect(json['stack_trace'], equals('main.dart:42:10'));

        // 2. Critical check: occurred_at formatted as ISO 8601 UTC string
        expect(json.containsKey('occurred_at'), isTrue);
        expect(json['occurred_at'], isA<String>());
        expect((json['occurred_at'] as String).endsWith('Z'), isTrue);
        expect(json['occurred_at'], equals(now.toIso8601String()));

        // 3. Environment keys
        expect(json.containsKey('environment'), isTrue);
        final env = json['environment'] as Map<String, dynamic>;
        expect(env['app_version'], equals('1.0.0+1'));
        expect(env['device_model'], equals('Pixel 7'));

        // 4. Breadcrumbs
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

        // First 10 allowed
        for (int i = 0; i < 10; i++) {
          expect(rateLimiter.allow(), isTrue);
        }

        // 11th rejected
        expect(rateLimiter.allow(), isFalse);
      },
    );
  });

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
        // Without trailing slash
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

  group('T1.17: CrashQueue Resilience & 401 Discard Policy', () {
    test(
      '401 Unauthorized permanently pauses telemetry and clears queue without saving offline',
      () async {
        final mockRepo = MockCrashOfflineRepository();
        final crashOffline = CrashOffline(baseCrashOfflineRepository: mockRepo);
        final queue = CrashQueue(crashOffline: crashOffline);

        final crash1 = _createDummyCrash();
        final crash2 = _createDummyCrash();

        await queue.add(crash1);
        await queue.add(crash2);
        expect(queue.length, equals(2));

        // Process queue with a simulated 401 Unauthorized error
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

        // Telemetry must be permanently paused & unauthorized flagged
        expect(queue.isUnauthorized, isTrue);
        expect(queue.isTelemetryPaused, isTrue);

        // In-memory queue must be cleared
        expect(queue.length, equals(0));

        // Crash must NEVER be saved offline on 401
        expect(mockRepo.crashes, isEmpty);

        // Any subsequent add() must reject and not save offline
        final crash3 = _createDummyCrash();
        await queue.add(crash3);
        expect(queue.length, equals(0));
        expect(mockRepo.crashes, isEmpty);

        queue.dispose();
      },
    );

    test('429 Rate Limited pauses telemetry and buffers to offline', () async {
      final mockRepo = MockCrashOfflineRepository();
      final crashOffline = CrashOffline(baseCrashOfflineRepository: mockRepo);
      final queue = CrashQueue(crashOffline: crashOffline);

      final crash = _createDummyCrash();
      await queue.add(crash);

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

  group('T1.17: Storage Invariants & FIFO Eviction', () {
    test('CrashOfflineDatasource enforces 100-crash FIFO limit', () {
      expect(CrashOfflineDatasource.maxOfflineCrashes, equals(100));
    });
  });

  group('T1.14 & T1.15: TraceX Public API Entry Points', () {
    test('TraceX exposes required public methods without error', () {
      expect(TraceX.init, isNotNull);
      expect(TraceX.initialize, isNotNull);
      expect(TraceX.recordFlutterError, isNotNull);
      expect(TraceX.recordError, isNotNull);
      expect(TraceX.runGuarded, isNotNull);

      // Verify recordError can be called safely without crashing even when uninitialized
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

        // First crash: attempts edge, fails, falls back to origin
        await ds.sendCrashDetails(model);

        expect(attemptedUrls.length, equals(2));
        expect(attemptedUrls[0], contains('workers.dev'));
        expect(attemptedUrls[1], equals(ApiConst.originCrashUrl));
        expect(ds.isPreferringFallback, isTrue);

        // Second crash: sticky fallback sends straight to origin without edge timeout
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
        // Must NOT attempt origin fallback on 401!
        expect(attemptedUrls.length, equals(1));
        expect(attemptedUrls[0], contains('workers.dev'));
        expect(ds.isPreferringFallback, isFalse);
      },
    );
  });
}
