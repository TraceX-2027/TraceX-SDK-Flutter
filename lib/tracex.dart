import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import 'package:tracex/core/services/crash_queue.dart';
import 'package:tracex/core/services/services_locator.dart';
import 'package:tracex/data/collectors/crash_rate_limiter.dart';
import 'package:tracex/domain/entities/crash.dart';
import 'package:tracex/domain/repositories/base_breadcrumb_repository.dart';
import 'package:tracex/domain/repositories/base_crash_repository.dart';
import 'package:tracex/domain/repositories/base_environment_repository.dart';
import 'package:tracex/domain/usecases/get_breadcrumb_details.dart';
import 'package:tracex/domain/usecases/get_environment_details.dart';
import 'package:tracex/domain/usecases/send_crash_details.dart';

class TraceX {
  TraceX._();

  static const String _platform = 'flutter';
  static const String _language = 'dart';

  static String? _projectKey;

  static SentCrashDetils? _sendCrashDetails;
  static GetEnvironmentDetails? _getEnvironmentDetails;
  static GetBreadcrumbDetails? _getBreadcrumbDetails;

  static CrashRateLimiter? _rateLimiter;
  static CrashQueue? _crashQueue;

  // الاحتفاظ بالمعلومات الأساسية للخطأ الأخير + توقيته لتفادي الحظر الدائم
  static String? _lastExceptionType;
  static String? _lastErrorMessage;
  static String? _lastStackTrace;
  static DateTime? _lastCrashTimestamp;

  static bool _initialized = false;
  static bool _initializing = false;

  static FlutterExceptionHandler? _previousFlutterErrorHandler;

  static bool Function(Object error, StackTrace stack)?
  _previousPlatformErrorHandler;

  static bool get isInitialized => _initialized;

  static String? get projectKey => _projectKey;

  // -----------------------------------------
  // Initialize
  // -----------------------------------------

  static Future<void> initialize({required String projectKey}) async {
    if (_initialized || _initializing) {
      return;
    }

    if (projectKey.trim().isEmpty) {
      throw ArgumentError('TraceX projectKey cannot be empty.');
    }

    _initializing = true;

    try {
      _projectKey = projectKey;
      WidgetsFlutterBinding.ensureInitialized();

      // Initialize services
      ServicesLocator.init();

      _sendCrashDetails = SentCrashDetils(
        baseCrashRepository: sl<BaseCrashRepository>(),
      );

      _getEnvironmentDetails = GetEnvironmentDetails(
        baseEnvironmentCollector: sl<BaseEnvironmentRepository>(),
      );

      _getBreadcrumbDetails = GetBreadcrumbDetails(
        baseBreadcrumbRepository: sl<BaseBreadcrumbRepository>(),
      );

      // Rate limiter
      _rateLimiter = CrashRateLimiter(
        maxCrashes: 10,
        window: const Duration(minutes: 1),
      );

      // Crash queue
      _crashQueue = CrashQueue(maxSize: 20, maxRetries: 3);

      // Initialize environment
      await _getEnvironmentDetails!.initialize();

      // -----------------------------------------
      // Flutter & Platform Error Handlers
      // -----------------------------------------

      _previousFlutterErrorHandler = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        unawaited(
          _captureException(
            details.exception,
            details.stack ?? StackTrace.current,
          ),
        );

        // Keep Flutter's default behavior
        _previousFlutterErrorHandler?.call(details);
      };

      _previousPlatformErrorHandler = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        unawaited(_captureException(error, stack));

        // Keep previous handler behavior
        return _previousPlatformErrorHandler?.call(error, stack) ?? false;
      };

      _initialized = true;

      debugPrint('TraceX: Initialized successfully.');
    } catch (e, stack) {
      debugPrint('TraceX: Initialization failed: $e');
      debugPrint('$stack');

      // -----------------------------------------
      // Cleanup / Rollback in case of failure
      // -----------------------------------------
      _initialized = false;

      // Restore previous error handlers
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
    final now = DateTime.now().toUtc();

    try {
      // 1. Check Deduplication FIRST (Synchronous & Zero Overhead)
      if (isDuplicate(
        exceptionType: exceptionType,
        errorMessage: errorMessage,
        stackTrace: stackTraceStr,
        timestamp: now,
      )) {
        debugPrint('TraceX: Duplicate crash ignored.');
        return;
      }

      // 2. Rate Limit Check (consumes quota only for UNIQUE errors)
      final rateLimiter = _rateLimiter;

      if (rateLimiter == null) {
        debugPrint('TraceX: Rate limiter is not initialized.');
        return;
      }

      if (!rateLimiter.allow()) {
        debugPrint('TraceX: Crash rate limit exceeded.');
        return;
      }

      // 3. Update Last Crash Cache immediately after passing checks
      _lastExceptionType = exceptionType;
      _lastErrorMessage = errorMessage;
      _lastStackTrace = stackTraceStr;
      _lastCrashTimestamp = now;

      // 4. Get dependencies
      final getEnvironmentDetails = _getEnvironmentDetails;
      final getBreadcrumbDetails = _getBreadcrumbDetails;
      final crashQueue = _crashQueue;
      final sendCrashDetails = _sendCrashDetails;

      if (getEnvironmentDetails == null ||
          getBreadcrumbDetails == null ||
          crashQueue == null ||
          sendCrashDetails == null) {
        debugPrint('TraceX: Required services are not initialized.');
        return;
      }

      // 5. Heavy Async Work (Collected ONLY for approved crashes)
      final environment = await getEnvironmentDetails.execute();
      final breadcrumbs = await getBreadcrumbDetails.execute();

      // 6. Build and Enqueue Crash
      final crash = Crash(
        projectKey: _projectKey!,
        platform: _platform,
        language: _language,
        timestamp: now,
        exceptionType: exceptionType,
        errorMessage: errorMessage,
        stackTrace: stackTraceStr,
        environment: environment,
        breadcrumbs: breadcrumbs,
      );

      crashQueue.add(crash);

      debugPrint(
        'TraceX: Crash added to queue '
        '(size: ${crashQueue.length})',
      );

      await crashQueue.process(sendCrashDetails.execute);
    } catch (e, stack) {
      debugPrint('TraceX: Failed to capture crash: $e');
      debugPrint('TraceX: $stack');
    }
  }

  // Helper method للتحقق السريع المباشر
  static bool isDuplicate({
    required String exceptionType,
    required String errorMessage,
    required String stackTrace,
    required DateTime timestamp,
    Duration cooldown = const Duration(minutes: 5),
  }) {
    if (_lastCrashTimestamp == null) return false;

    final isSameException =
        _lastExceptionType == exceptionType &&
        _lastErrorMessage == errorMessage &&
        _lastStackTrace == stackTrace;

    if (!isSameException) return false;

    return timestamp.difference(_lastCrashTimestamp!) < cooldown;
  }
}
