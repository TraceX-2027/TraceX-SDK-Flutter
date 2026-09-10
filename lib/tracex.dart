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
import 'package:tracex/domain/usecases/sent_crash_detiles.dart';

class TraceX {
  TraceX._();

  static const String _platform = 'flutter';
  static const String _language = 'dart';

  static String? _projectKey;

  static SentCrashDetiles? _sendCrashDetails;
  static GetEnvironmentDetails? _getEnvironmentDetails;
  static GetBreadcrumbDetails? _getBreadcrumbDetails;

  static CrashRateLimiter? _rateLimiter;
  static CrashQueue? _crashQueue;
  static Crash? _crashLast;

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

      _sendCrashDetails = SentCrashDetiles(
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
      // Flutter errors
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

      // -----------------------------------------
      // Platform errors
      // -----------------------------------------

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

      _initialized = false;
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

    // =========================================================
    // From here we can use await safely
    // =========================================================

    try {
      // -----------------------------------------
      // Rate Limit
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
      // Get dependencies
      // -----------------------------------------

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

      // -----------------------------------------
      // Collect Environment
      // -----------------------------------------

      final environment = await getEnvironmentDetails.execute();

      // -----------------------------------------
      // Collect Breadcrumbs
      // -----------------------------------------

      final breadcrumbs = await getBreadcrumbDetails.execute();

      // -----------------------------------------
      // Build Crash
      // -----------------------------------------

      final crash = Crash(
        projectKey: _projectKey!,
        platform: _platform,
        language: _language,
        timestamp: DateTime.now().toUtc(),
        exceptionType: exceptionType,
        errorMessage: errorMessage,
        stackTrace: stackTrace.toString(),
        environment: environment,
        breadcrumbs: breadcrumbs,
      );

      // -----------------------------------------
      // Add Crash To Queue
      // -----------------------------------------
      if (_crashLast == null || !isDuplicate(crash, _crashLast!)) {
        _crashLast = crash;

        crashQueue.add(crash);

        debugPrint(
          'TraceX: Crash added to queue '
          '(size: ${crashQueue.length})',
        );

        await crashQueue.process(sendCrashDetails.execute);
      } else {
        debugPrint('TraceX: Duplicate crash ignored.');
      }
    } catch (e, stack) {
      debugPrint('TraceX: Failed to capture crash: $e');

      debugPrint('TraceX: $stack');
    }
  }
}

bool isDuplicate(
  Crash crash,
  Crash lastCrash, {
  Duration cooldown = const Duration(minutes: 5),
}) {
  final isSameException =
      crash.exceptionType == lastCrash.exceptionType &&
      crash.errorMessage == lastCrash.errorMessage &&
      crash.stackTrace == lastCrash.stackTrace;

  if (!isSameException) return false;

  return crash.timestamp.difference(lastCrash.timestamp) < cooldown;
}
