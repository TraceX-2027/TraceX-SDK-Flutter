import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:tracex/core/services/crash_queue.dart';
import 'package:tracex/core/services/services_locator.dart';
import 'package:tracex/core/services/crash_rate_limiter.dart';
import 'package:tracex/domain/entities/breadcrumb.dart';
import 'package:tracex/domain/entities/crash.dart';
import 'package:tracex/domain/usecases/get_breadcrumb_details.dart';
import 'package:tracex/domain/usecases/get_environment_details.dart';
import 'package:tracex/domain/usecases/save_offline_crash.dart';
import 'package:tracex/domain/usecases/send_crash_details.dart';

class TraceX {
  TraceX._();

  static const String _platform = 'flutter';
  static const String _language = 'dart';

  static String? _projectKey;

  static SendCrashDetails? _sendCrashDetails;
  static GetEnvironmentDetails? _getEnvironmentDetails;
  static GetBreadcrumbDetails? _getBreadcrumbDetails;
  static CrashOffline? _crashOffline;

  static CrashRateLimiter? _rateLimiter;
  static CrashQueue? _crashQueue;

  static final Map<int, DateTime> _crashHistory = {};

  static bool _initialized = false;
  static bool _initializing = false;

  static bool _offlineBuffer = true;
  static bool _captureBreadcrumbs = true;

  static FlutterExceptionHandler? _previousFlutterErrorHandler;
  static bool Function(Object error, StackTrace stack)?
  _previousPlatformErrorHandler;

  // -----------------------------------------
  // Initialize
  // -----------------------------------------

  static Future<void> initialize({
    required String projectKey,
    bool offlineBuffer = true,
    bool captureBreadcrumbs = true,
  }) async {
    if (_initialized || _initializing) {
      return;
    }

    if (projectKey.trim().isEmpty) {
      throw ArgumentError('TraceX projectKey cannot be empty.');
    }

    _initializing = true;

    try {
      _projectKey = projectKey;

      _offlineBuffer = offlineBuffer;
      _captureBreadcrumbs = captureBreadcrumbs;

      WidgetsFlutterBinding.ensureInitialized();

      // -----------------------------------------
      // Initialize Services
      // -----------------------------------------

      await ServicesLocator.init();

      // -----------------------------------------
      // Get Dependencies From GetIt
      // -----------------------------------------

      _sendCrashDetails = sl<SendCrashDetails>();
      _getEnvironmentDetails = sl<GetEnvironmentDetails>();
      _getBreadcrumbDetails = sl<GetBreadcrumbDetails>();
      _crashOffline = sl<CrashOffline>();

      // -----------------------------------------
      // Rate Limiter
      // -----------------------------------------

      _rateLimiter = CrashRateLimiter();

      // -----------------------------------------
      // Crash Queue
      // -----------------------------------------

      _crashQueue = CrashQueue(
        crashOffline: _crashOffline!,
        offlineBuffer: _offlineBuffer,
      );

      // -----------------------------------------
      // Start Offline Retry
      // -----------------------------------------

      if (_offlineBuffer) {
        _crashQueue!.startOfflineRetry(_sendCrashDetails!.execute);
      }

      // -----------------------------------------
      // Initialize Environment
      // -----------------------------------------

      await _getEnvironmentDetails!.initialize();

      // -----------------------------------------
      // Flutter Error Handler
      // -----------------------------------------

      _previousFlutterErrorHandler = FlutterError.onError;

      //  FlutterError.onError:
      FlutterError.onError = (FlutterErrorDetails details) {
        scheduleMicrotask(() {
          _captureException(
            details.exception,
            details.stack ?? StackTrace.current,
          );
        });
        _previousFlutterErrorHandler?.call(details);
      };

      //  PlatformDispatcher.instance.onError:
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        scheduleMicrotask(() {
          _captureException(error, stack);
        });
        return _previousPlatformErrorHandler?.call(error, stack) ?? false;
      };
      _initialized = true;

      debugPrint('TraceX: Initialized successfully.');
    } catch (e, stack) {
      debugPrint('TraceX: Initialization failed: $e');
      debugPrint('$stack');

      // -----------------------------------------
      // Cleanup
      // -----------------------------------------
      await ServicesLocator.reset();

      _initialized = false;
      _crashHistory.clear();

      _crashQueue?.dispose();
      _crashQueue = null;
      _rateLimiter = null;

      _sendCrashDetails = null;
      _getEnvironmentDetails = null;
      _getBreadcrumbDetails = null;
      _crashOffline = null;

      // Restore previous handlers
      FlutterError.onError = _previousFlutterErrorHandler;
      PlatformDispatcher.instance.onError = _previousPlatformErrorHandler;

      rethrow;
    } finally {
      _initializing = false;
    }
  }

  // -----------------------------------------
  // Capture Exception
  // -----------------------------------------

  static Future<void> _captureException(
    Object error,
    StackTrace stackTrace,
  ) async {
    if (!_initialized) {
      debugPrint(
        'TraceX: Ignored exception because TraceX is not initialized.',
      );
      return;
    }

    final exceptionType = error.runtimeType.toString();
    final errorMessage = error.toString();
    final stackTraceStr = stackTrace.toString();
    final occurredAt = DateTime.now().toUtc();
    try {
      // -----------------------------------------
      // 1. Deduplication
      // -----------------------------------------

      if (_isDuplicate(
        exceptionType: exceptionType,
        stackTrace: stackTraceStr,
        occurredAt: occurredAt,
      )) {
        debugPrint('TraceX: Duplicate crash ignored.');
        return;
      }

      // -----------------------------------------
      // 2. Rate Limit
      // -----------------------------------------

      final rateLimiter = _rateLimiter;
      if (rateLimiter == null) {
        debugPrint('TraceX: Rate limiter is not initialized.');
        return;
      }

      if (!rateLimiter.allow()) {
        debugPrint('TraceX: Crash rate limit exceeded.');
        return;
      }

      // -----------------------------------------
      // 3. Get Dependencies
      // -----------------------------------------

      final getEnvironmentDetails = _getEnvironmentDetails;
      final getBreadcrumbDetails = _getBreadcrumbDetails;
      final crashQueue = _crashQueue;
      final sendCrashDetails = _sendCrashDetails;

      if (getEnvironmentDetails == null ||
          crashQueue == null ||
          sendCrashDetails == null) {
        debugPrint('TraceX: Required services are not initialized.');
        return;
      }

      // -----------------------------------------
      // 4. Collect Environment
      // -----------------------------------------

      final environment = await getEnvironmentDetails.execute();

      // -----------------------------------------
      // 5. Collect Breadcrumbs
      // -----------------------------------------

      final breadcrumbs = _captureBreadcrumbs && getBreadcrumbDetails != null
          ? await getBreadcrumbDetails.execute()
          : <Breadcrumb>[];

      // -----------------------------------------
      // 6. Build Crash
      // -----------------------------------------

      final crash = Crash(
        projectKey: _projectKey!,
        platform: _platform,
        language: _language,
        occurredAt: occurredAt,
        exceptionType: exceptionType,
        errorMessage: errorMessage,
        stackTrace: stackTraceStr,
        environment: environment,
        breadcrumbs: breadcrumbs,
      );

      // -----------------------------------------
      // 7. Add Crash To Queue
      // -----------------------------------------

      await crashQueue.add(crash);

      debugPrint('TraceX: Crash added to queue (size: ${crashQueue.length})');

      // -----------------------------------------
      // 8. Process Queue
      // -----------------------------------------

      await crashQueue.process(sendCrashDetails.execute);
    } catch (e, stack) {
      debugPrint('TraceX: Failed to capture crash: $e');
      debugPrint('TraceX: $stack');
    }
  }

  // -----------------------------------------
  // Deduplication Fingerprinting
  // -----------------------------------------

  static bool _isDuplicate({
    required String exceptionType,
    required String stackTrace,
    required DateTime occurredAt,
    Duration cooldown = const Duration(minutes: 5),
  }) {
    final stackLines = stackTrace.trim().split('\n').take(2).join('\n');

    final fingerprint = Object.hash(exceptionType, stackLines);

    final lastSeen = _crashHistory[fingerprint];

    if (lastSeen != null && occurredAt.difference(lastSeen) < cooldown) {
      return true;
    }

    _crashHistory[fingerprint] = occurredAt;

    if (_crashHistory.length > 50) {
      _crashHistory.remove(_crashHistory.keys.first);
    }

    return false;
  }
}
