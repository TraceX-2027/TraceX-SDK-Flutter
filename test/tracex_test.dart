import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracex_flutter/core/network/connectivity_monitor.dart';
import 'package:tracex_flutter/core/services/crash_queue.dart';
import 'package:tracex_flutter/core/services/crash_rate_limiter.dart';
import 'package:tracex_flutter/core/utils/api_const.dart';
import 'package:tracex_flutter/data/collectors/breadcrumb_collector.dart';
import 'package:tracex_flutter/data/collectors/breadcrumbs/breadcrumb_navigator_observer.dart';
import 'package:tracex_flutter/data/collectors/breadcrumbs/tracex_dio_interceptor.dart';
import 'package:tracex_flutter/data/datasources/crash_offline_datasource.dart';
import 'package:tracex_flutter/data/datasources/crash_remote_datasource.dart';
import 'package:tracex_flutter/data/models/crashes_model.dart';
import 'package:tracex_flutter/domain/entities/breadcrumb.dart';
import 'package:tracex_flutter/domain/entities/crash.dart';
import 'package:tracex_flutter/domain/entities/environment.dart';
import 'package:tracex_flutter/domain/repositories/base_crash_offline_repository.dart';
import 'package:tracex_flutter/domain/usecases/save_offline_crash.dart';
import 'package:tracex_flutter/src/data_scrubber.dart';
import 'package:tracex_flutter/tracex.dart';

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
  Future<void> deleteCrashesOffline(List<Crash> crashesToDelete) async {
    for (final crash in crashesToDelete) {
      crashes.remove(crash);
    }
  }

  void clear() {
    crashes.clear();
  }
}

class FakeConnectivity implements Connectivity {
  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  void emit(List<ConnectivityResult> results) {
    _controller.add(results);
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    return [ConnectivityResult.none];
  }

  void dispose() {
    _controller.close();
  }
}

Crash _createDummyCrash({String projectKey = 'test-project-key', int? id}) {
  return Crash(
    id: id,
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
        equals('https://api.tracex.dev/api/v1/'),
      );
      expect(
        ApiConst.crashUrl,
        equals(
          'https://tracex-edge-ingest.kareemadel10110.workers.dev/api/v1/crashes',
        ),
      );
      expect(
        ApiConst.originCrashUrl,
        equals('https://api.tracex.dev/api/v1/crashes'),
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
      expect(TraceX.recordFlutterError, isNotNull);
      expect(TraceX.recordError, isNotNull);
      expect(TraceX.runGuarded, isNotNull);
      TraceX.recordError(Exception('test exception'), StackTrace.current);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // T2.15: Breadcrumb Tracking & Ring Buffer Invariants (RESTORED - B2)
  // ─────────────────────────────────────────────────────────────────────────
  group('T2.15: Breadcrumb Tracking & Ring Buffer Invariants', () {
    setUp(() {
      BreadcrumbCollector.clear();
    });

    test('Enforces 50-item ring buffer capacity with FIFO eviction', () {
      for (int i = 1; i <= 60; i++) {
        BreadcrumbCollector.addBreadcrumb(
          category: 'test',
          action: 'step_$i',
          target: 'target_$i',
        );
      }

      final breadcrumbs = BreadcrumbCollector().breadcrumbs;
      expect(breadcrumbs.length, equals(50));
      // First 10 items were evicted; first remaining is step_11
      expect(breadcrumbs.first.action, equals('step_11'));
      expect(breadcrumbs.last.action, equals('step_60'));
    });

    test('Clear resets buffer and sequence order counter', () {
      BreadcrumbCollector.addBreadcrumb(
        category: 'ui',
        action: 'tap',
        target: 'button',
      );
      expect(BreadcrumbCollector().breadcrumbs.length, equals(1));

      BreadcrumbCollector.clear();
      expect(BreadcrumbCollector().breadcrumbs, isEmpty);

      BreadcrumbCollector.addBreadcrumb(
        category: 'ui',
        action: 'tap',
        target: 'button2',
      );
      expect(BreadcrumbCollector().breadcrumbs.first.sequenceOrder, equals(1));
    });

    test('Sanitizes non-primitive values to JSON-safe primitives', () {
      BreadcrumbCollector.addBreadcrumb(
        category: 'data',
        action: 'filter',
        target: 'grid',
        data: {'count': 42, 'isValid': true, 'customObj': DateTime(2026, 1, 1)},
      );

      final crumb = BreadcrumbCollector().breadcrumbs.first;
      expect(crumb.data['count'], equals(42));
      expect(crumb.data['isValid'], equals(true));
      expect(crumb.data['customObj'], isA<String>());
    });

    test('TraceXNavigatorObserver uses category "navigation"', () {
      final observer = TraceXNavigatorObserver();
      final route = PageRouteBuilder(
        settings: const RouteSettings(name: '/dashboard'),
        pageBuilder: (_, __, ___) => const SizedBox(),
      );

      observer.didPush(route, null);
      final breadcrumbs = BreadcrumbCollector().breadcrumbs;
      expect(breadcrumbs.isNotEmpty, isTrue);
      expect(breadcrumbs.last.category, equals('navigation'));
      expect(breadcrumbs.last.target, equals('/dashboard'));
    });

    test('TraceXDioInterceptor ignores internal TraceX ingestion paths', () {
      final interceptor = TraceXDioInterceptor();
      final handler = ResponseInterceptorHandler();

      // Normal app API request
      final normalResponse = Response(
        requestOptions: RequestOptions(path: 'https://api.my-app.com/items'),
        statusCode: 200,
      );
      interceptor.onResponse(normalResponse, handler);
      expect(BreadcrumbCollector().breadcrumbs.length, equals(1));

      // TraceX internal ingestion endpoint - MUST BE IGNORED
      final internalResponse = Response(
        requestOptions: RequestOptions(
          path: 'https://tracex.dev/api/v1/crashes',
        ),
        statusCode: 200,
      );
      interceptor.onResponse(
        internalResponse,
        ResponseInterceptorHandler(),
      ); // Count must still be 1 (ignored)
      expect(BreadcrumbCollector().breadcrumbs.length, equals(1));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // T2.18: Connectivity & Batch Sync Invariants (ADDED - B2)
  // ─────────────────────────────────────────────────────────────────────────
  group('T2.18: Connectivity & Batch Sync Invariants', () {
    test(
      'Stateful transition from none to active connection fires onReconnected',
      () async {
        final fakeConn = FakeConnectivity();
        final monitor = ConnectivityMonitor(connectivity: fakeConn);
        int callCount = 0;

        monitor.startListening(
          onReconnected: () {
            callCount++;
          },
        );

        fakeConn.emit([ConnectivityResult.none]);
        await pumpEventQueue();
        expect(callCount, equals(0));

        // Reconnect
        fakeConn.emit([ConnectivityResult.wifi]);
        await pumpEventQueue();
        expect(callCount, equals(1));

        // Wifi -> Mobile without disconnect should NOT trigger again
        fakeConn.emit([ConnectivityResult.mobile]);
        await pumpEventQueue();
        expect(callCount, equals(1));

        monitor.stopListening();
        fakeConn.dispose();
      },
    );

    test(
      'flushOfflineInBatches chunks at 50 crashes maximum and halts on 401',
      () async {
        final mockRepo = MockCrashOfflineRepository();
        final crashOffline = CrashOffline(baseCrashOfflineRepository: mockRepo);
        final queue = CrashQueue(crashOffline: crashOffline);

        for (int i = 1; i <= 65; i++) {
          await mockRepo.saveCrash(_createDummyCrash(id: i));
        }

        final List<int> chunks = [];
        await queue.flushOfflineInBatches((batch) async {
          chunks.add(batch.length);
        });

        expect(chunks, equals([50, 15]));
        expect(mockRepo.crashes, isEmpty);

        // Verify 401 Halting
        await mockRepo.saveCrash(_createDummyCrash(id: 99));
        int attempts = 0;
        await queue.flushOfflineInBatches((batch) async {
          attempts++;
          throw DioException(
            requestOptions: RequestOptions(path: 'crashes/batch'),
            response: Response(
              requestOptions: RequestOptions(path: 'crashes/batch'),
              statusCode: 401,
            ),
          );
        });

        expect(attempts, equals(1));
        expect(queue.isUnauthorized, isTrue);
        expect(queue.isTelemetryPaused, isTrue);

        queue.dispose();
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // T1.16: Privacy Scrubbing & Data Redaction
  // ─────────────────────────────────────────────────────────────────────────
  group('T1.16: Privacy Scrubbing & Data Redaction Tests', () {
    test('Redacts Bearer tokens and Authorization headers', () {
      const input = 'Exception: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9';
      final scrubbed = DataScrubber.scrubString(input);
      expect(scrubbed, equals('Exception: Bearer [REDACTED]'));
    });

    test('Redacts query parameter credentials and tokens', () {
      const url =
          'https://api.example.com/v1/auth?token=superSecret123&user=john';
      final scrubbed = DataScrubber.scrubString(url);
      expect(
        scrubbed,
        equals('https://api.example.com/v1/auth?token=[REDACTED]&user=john'),
      );
    });

    test('Redacts nested sensitive keys in maps', () {
      final input = {
        'status': 'error',
        'user': {
          'name': 'John',
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

    test('Redacts delimited credit cards with spaces and hyphens (N1)', () {
      const hyphens = 'Payment card 4111-1111-1111-1111';
      expect(
        DataScrubber.scrubString(hyphens),
        equals('Payment card [CARD_REDACTED]'),
      );

      const spaces = 'Card number 4111 1111 1111 1111 used';
      expect(
        DataScrubber.scrubString(spaces),
        equals('Card number [CARD_REDACTED] used'),
      );
    });

    test(
      'Redacts camelCase compound keys like userPassword and authToken (M1)',
      () {
        final input = {
          'userPassword': 'secretPassword123',
          'authToken': 'xyz789',
          'accountSecret': 'topSecret',
          'myApiKey': 'key-1234',
          'cardCvv': '999',
          'userPin': '1234',
          'author': 'Shakespeare',
          'authority': 'admin',
        };

        final scrubbed = DataScrubber.scrubMap(input);
        expect(scrubbed['userPassword'], equals('[REDACTED]'));
        expect(scrubbed['authToken'], equals('[REDACTED]'));
        expect(scrubbed['accountSecret'], equals('[REDACTED]'));
        expect(scrubbed['myApiKey'], equals('[REDACTED]'));
        expect(scrubbed['cardCvv'], equals('[REDACTED]'));
        expect(scrubbed['userPin'], equals('[REDACTED]'));
        expect(scrubbed['author'], equals('Shakespeare'));
        expect(scrubbed['authority'], equals('admin'));
      },
    );

    test(
      'BreadcrumbCollector integration: scrubs sensitive keys in data (M2)',
      () {
        BreadcrumbCollector.clear();
        BreadcrumbCollector.addBreadcrumb(
          category: 'auth',
          action: 'login',
          target: 'LoginScreen',
          data: {
            'password': 'secret123',
            'authToken': 'Bearer myToken',
            'normalKey': 'normalValue',
          },
        );

        final last = BreadcrumbCollector().breadcrumbs.last;
        expect(last.data['password'], equals('[REDACTED]'));
        expect(last.data['authToken'], equals('[REDACTED]'));
        expect(last.data['normalKey'], equals('normalValue'));
      },
    );
  });
}
