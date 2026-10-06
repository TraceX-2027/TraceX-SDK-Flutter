import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tracex/core/services/crash_queue.dart';
import 'package:tracex/core/services/crash_rate_limiter.dart';
import 'package:tracex/core/services/services_locator.dart';
import 'package:tracex/data/collectors/breadcrumb_collector.dart';
import 'package:tracex/core/utils/api_const.dart';
import 'package:tracex/domain/entities/breadcrumb.dart';
import 'package:tracex/domain/entities/crash.dart';
import 'package:tracex/domain/usecases/get_breadcrumb_details.dart';
import 'package:tracex/domain/usecases/get_environment_details.dart';
import 'package:tracex/domain/usecases/save_offline_crash.dart';
import 'package:tracex/domain/usecases/send_crash_details.dart';
import 'package:tracex/src/data_scrubber.dart';
// Public API exports - breadcrumb collectors and entities (B1 Fix)
export 'data/collectors/breadcrumb_collector.dart';
export 'data/collectors/breadcrumbs/breadcrumb_navigator_observer.dart';
export 'data/collectors/breadcrumbs/tracex_dio_interceptor.dart';
export 'data/collectors/breadcrumbs/tracex_user_interaction.dart';
export 'domain/entities/breadcrumb.dart';

class TraceX {
  TraceX._();

  static const String defaultEndpoint = ApiConst.edgeBaseUrl;
  static const String originEndpoint = ApiConst.originBaseUrl;

  static const String _platform = 'flutter';
  static const String _language = 'dart';

  static String? _projectKey;
  static bool _enableLogging = false;

  /// Alias for [initialize] to adhere to standard Flutter SDK naming conventions
  static Future<void> init({
    String? projectKey,
    String? apiKey,
    String? endpoint,
    String? fallbackEndpoint,
    bool enableLogging = false,
    bool offlineBuffer = true,
    bool captureBreadcrumbs = true,
  }) => initialize(
    projectKey: projectKey,
    apiKey: apiKey,
    endpoint: endpoint,
    fallbackEndpoint: fallbackEndpoint,
    enableLogging: enableLogging,
    offlineBuffer: offlineBuffer,
    captureBreadcrumbs: captureBreadcrumbs,
  );

  static SendCrashDetails? _sendCrashDetails;
  static GetEnvironmentDetails? _getEnvironmentDetails;
  static GetBreadcrumbDetails? _getBreadcrumbDetails;
  static CrashOffline? _crashOffline;

  static CrashRateLimiter? _rateLimiter;
  static CrashQueue? _crashQueue;

  // سجل بصمات الكراشات لمنع التكرار بدقة عالية
  static final Map<int, DateTime> _crashHistory = {};

  static bool _initialized = false;
  static bool _initializing = false;

  static bool _offlineBuffer = true;
  static bool _captureBreadcrumbs = true;

  static bool get isInitialized => _initialized;

  static String? get projectKey => _projectKey;

  static int get queueLength => _crashQueue?.length ?? 0;

  @visibleForTesting
  static CrashQueue? get crashQueue => _crashQueue;

  /// Optional listener for diagnostic events and lifecycle logs
  static void Function(String message)? onDiagnosticLog;

  static FlutterExceptionHandler? _previousFlutterErrorHandler;
  static bool Function(Object error, StackTrace stack)?
  _previousPlatformErrorHandler;

  static void _log(String message) {
    if (_enableLogging) {
      debugPrint(message);
    }
    try {
      onDiagnosticLog?.call(message);
    } catch (_) {}
  }

  // -----------------------------------------
  // Initialize
  // -----------------------------------------

  static Future<void> initialize({
    String? projectKey,
    String? apiKey,
    String? endpoint,
    String? fallbackEndpoint,
    bool enableLogging = false,
    bool offlineBuffer = true,
    bool captureBreadcrumbs = true,
  }) async {
    if (_initialized || _initializing) {
      return;
    }

    final effectiveKey = (projectKey != null && projectKey.trim().isNotEmpty)
        ? projectKey.trim()
        : (apiKey != null && apiKey.trim().isNotEmpty)
        ? apiKey.trim()
        : null;

    if (effectiveKey == null) {
      throw ArgumentError('TraceX projectKey (or apiKey) cannot be empty.');
    }

    _initializing = true;

    try {
      _projectKey = effectiveKey;
      _enableLogging = enableLogging;
      _offlineBuffer = offlineBuffer;
      _captureBreadcrumbs = captureBreadcrumbs;

      final targetEndpoint = (endpoint != null && endpoint.trim().isNotEmpty)
          ? endpoint.trim()
          : defaultEndpoint;

      WidgetsFlutterBinding.ensureInitialized();

      // -----------------------------------------
      // Initialize Services with Target Endpoint & Fallback
      // -----------------------------------------

      await ServicesLocator.init(
        endpoint: targetEndpoint,
        fallbackEndpoint: fallbackEndpoint,
      );

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
      // Flutter Error Handler (Microtask Queue)
      // -----------------------------------------

      _previousFlutterErrorHandler = FlutterError.onError;

      FlutterError.onError = (FlutterErrorDetails details) {
        recordFlutterError(details);
        _previousFlutterErrorHandler?.call(details);
      };

      // -----------------------------------------
      // Platform Error Handler (Microtask Queue)
      // -----------------------------------------

      _previousPlatformErrorHandler = PlatformDispatcher.instance.onError;

      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        scheduleMicrotask(() {
          _captureException(error, stack);
        });

        return _previousPlatformErrorHandler?.call(error, stack) ?? false;
      };

      _initialized = true;

      _log('TraceX: Initialized successfully with endpoint: $targetEndpoint');
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

  /// Records a Flutter framework error directly.
  /// Can be assigned to [FlutterError.onError].
  static void recordFlutterError(FlutterErrorDetails details) {
    scheduleMicrotask(() {
      _captureException(details.exception, details.stack ?? StackTrace.current);
    });
  }

  /// Manually records a caught error or exception.
  static void recordError(
    dynamic error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) {
    final effectiveError = (reason != null && reason.isNotEmpty)
        ? '$error (Reason: $reason)'
        : error;
    scheduleMicrotask(() {
      _captureException(effectiveError as Object, stack ?? StackTrace.current);
    });
  }

  /// Runs the app callback within a guarded zone to capture all unhandled asynchronous errors.
  static void runGuarded(void Function() appRunner) {
    runZonedGuarded(appRunner, (error, stack) {
      scheduleMicrotask(() {
        _captureException(error, stack);
      });
    });
  }

  /// Resets TraceX state and dependencies. Intended for testing purposes.
  @visibleForTesting
  static Future<void> reset() async {
    await ServicesLocator.reset();
    _initialized = false;
    _initializing = false;
    _projectKey = null;
    _enableLogging = false;
    _crashHistory.clear();
    _crashQueue?.dispose();
    _crashQueue = null;
    _rateLimiter = null;
    _sendCrashDetails = null;
    _getEnvironmentDetails = null;
    _getBreadcrumbDetails = null;
    _crashOffline = null;
    FlutterError.onError = _previousFlutterErrorHandler;
    PlatformDispatcher.instance.onError = _previousPlatformErrorHandler;
  }

  static void recordBreadcrumb({
    required String category,
    required String action,
    required String target,
    Map<String, dynamic> data = const {},
  }) {
    BreadcrumbCollector.addBreadcrumb(
      category: category,
      action: action,
      target: target,
      data: data,
    );
  }
  // -----------------------------------------
  // Capture Exception
  // -----------------------------------------

  static Future<void> _captureException(
    Object error,
    StackTrace stackTrace,
  ) async {
    if (!_initialized) {
      _log('TraceX: Ignored exception because TraceX is not initialized.');
      return;
    }

    final exceptionType = error.runtimeType.toString();
    final errorMessage = error.toString();
    final stackTraceStr = stackTrace.toString();
    final occurredAt = DateTime.now().toUtc();

    try {
      // -----------------------------------------
      // 1. Deduplication (خوارزمية منع التكرار بالبصمة)
      // -----------------------------------------

      if (_isDuplicate(
        exceptionType: exceptionType,
        errorMessage: errorMessage,
        stackTrace: stackTraceStr,
        timestamp: occurredAt,
      )) {
        _log('TraceX: Duplicate crash ignored.');
        return;
      }

      // -----------------------------------------
      // 2. Rate Limit
      // -----------------------------------------

      final rateLimiter = _rateLimiter;
      if (rateLimiter == null) {
        _log('TraceX: Rate limiter is not initialized.');
        return;
      }

      if (!rateLimiter.allow()) {
        _log('TraceX: Crash rate limit exceeded.');
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
        _log('TraceX: Required services are not initialized.');
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
      // 6. Build Crash (Standardized occurredAt)
      // -----------------------------------------

      final scrubbedErrorMessage = DataScrubber.scrubString(errorMessage);
      final scrubbedStackTrace = DataScrubber.scrubString(stackTraceStr);

      final crash = Crash(
        projectKey: _projectKey!,
        platform: _platform,
        language: _language,
        occurredAt: occurredAt,
        exceptionType: exceptionType,
        errorMessage: scrubbedErrorMessage,
        stackTrace: scrubbedStackTrace,
        environment: environment,
        breadcrumbs: breadcrumbs,
      );

      // -----------------------------------------
      // 7. Add Crash To Queue
      // -----------------------------------------

      await crashQueue.add(crash);

      _log('TraceX: Crash added to queue (size: ${crashQueue.length})');

      // -----------------------------------------
      // 8. Process Queue
      // -----------------------------------------

      await crashQueue.process(sendCrashDetails.execute);
      _log('TraceX: Processed queue for $exceptionType');
    } catch (e, stack) {
      _log('TraceX: Failed to capture crash: $e');
      debugPrint('TraceX: Failed to capture crash: $e');
      debugPrint('TraceX: $stack');
    }
  }

  // -----------------------------------------
  // Deduplication Fingerprinting
  // -----------------------------------------

  static bool _isDuplicate({
    required String exceptionType,
    required String errorMessage,
    required String stackTrace,
    required DateTime timestamp,
    Duration cooldown = const Duration(minutes: 5),
  }) {
    final stackLines = stackTrace.trim().split('\n').take(2).join('\n');

    final fingerprint = Object.hash(exceptionType, errorMessage, stackLines);

    final lastSeen = _crashHistory[fingerprint];

    if (lastSeen != null && timestamp.difference(lastSeen) < cooldown) {
      return true;
    }

    _crashHistory[fingerprint] = timestamp;

    if (_crashHistory.length > 50) {
      _crashHistory.remove(_crashHistory.keys.first);
    }

    return false;
  }
}
