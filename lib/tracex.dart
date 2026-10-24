import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:tracex_flutter/core/network/connectivity_monitor.dart';
import 'package:tracex_flutter/core/services/crash_queue.dart';
import 'package:tracex_flutter/core/services/crash_rate_limiter.dart';
import 'package:tracex_flutter/core/services/services_locator.dart';
import 'package:tracex_flutter/data/collectors/breadcrumb_collector.dart';
import 'package:tracex_flutter/core/utils/api_const.dart';
import 'package:tracex_flutter/data/collectors/breadcrumbs/breadcrumb_navigator_observer.dart';
import 'package:tracex_flutter/data/collectors/breadcrumbs/tracex_user_interaction_widget.dart';
import 'package:tracex_flutter/domain/entities/breadcrumb.dart';
import 'package:tracex_flutter/domain/entities/crash.dart';
import 'package:tracex_flutter/domain/usecases/get_breadcrumb_details.dart';
import 'package:tracex_flutter/domain/usecases/get_environment_details.dart';
import 'package:tracex_flutter/domain/usecases/save_offline_crash.dart';
import 'package:tracex_flutter/domain/usecases/send_batch_crash_details.dart';
import 'package:tracex_flutter/domain/usecases/send_crash_details.dart';
import 'package:tracex_flutter/src/data_scrubber.dart';
// Public API exports - breadcrumb collectors and entities (B1 Fix)
export 'data/collectors/breadcrumb_collector.dart';
export 'data/collectors/breadcrumbs/breadcrumb_navigator_observer.dart';
export 'data/collectors/breadcrumbs/tracex_dio_interceptor.dart';
export 'data/collectors/breadcrumbs/tracex_user_interaction_widget.dart';
export 'domain/entities/breadcrumb.dart';
export 'src/data_scrubber.dart';

/// Main entrypoint for TraceX crash capture, breadcrumb tracking, and forensic telemetry in Flutter applications.
class TraceX {
  TraceX._();

  /// Default Cloudflare Edge ingestion endpoint URL.
  static const String defaultEndpoint = ApiConst.edgeBaseUrl;

  /// Default Origin ingestion endpoint URL.
  static const String originEndpoint = ApiConst.originBaseUrl;

  static const String _platform = 'flutter';
  static const String _language = 'dart';

  static String? _projectKey;
  static bool _enableLogging = false;

  static SendCrashDetails? _sendCrashDetails;
  static GetEnvironmentDetails? _getEnvironmentDetails;
  static GetBreadcrumbDetails? _getBreadcrumbDetails;
  static CrashOffline? _crashOffline;
  static ConnectivityMonitor? _connectivityMonitor;

  static CrashRateLimiter? _rateLimiter;
  static CrashQueue? _crashQueue;

  static final Map<int, DateTime> _crashHistory = {};

  static bool _initialized = false;
  static bool _initializing = false;

  static bool _offlineBuffer = true;
  static bool _captureBreadcrumbs = true;

  /// Whether the TraceX SDK has completed initialization.
  static bool get isInitialized => _initialized;

  /// The active project API key configured for telemetry ingestion.
  static String? get projectKey => _projectKey;

  /// Number of crash payloads currently queued for transmission or offline storage.
  static int get queueLength => _crashQueue?.length ?? 0;

  /// The internal crash transmission queue instance.
  @visibleForTesting
  static CrashQueue? get crashQueue => _crashQueue;

  /// Optional listener for diagnostic events and lifecycle logs.
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

  static Future<MaterialApp> init({
    required String projectKey,
    required MaterialApp app,
    String? apiKey,
    String? endpoint,
    String? fallbackEndpoint,
    bool enableLogging = false,
    bool offlineBuffer = true,
    bool captureBreadcrumbs = true,
  }) async {
    if (_initialized || _initializing) {
      return _wrapMaterialApp(app);
    }

    final effectiveKey = (projectKey.trim().isNotEmpty)
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

      _connectivityMonitor = ConnectivityMonitor();
      _connectivityMonitor!.startListening(
        onReconnected: () {
          final sendBatch = sl<SendBatchCrashDetails>();
          _crashQueue?.flushOfflineInBatches(sendBatch.execute);
        },
      );

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

      return _wrapMaterialApp(app);
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
      _connectivityMonitor?.stopListening();
      _connectivityMonitor = null;

      // Restore previous handlers
      FlutterError.onError = _previousFlutterErrorHandler;
      PlatformDispatcher.instance.onError = _previousPlatformErrorHandler;

      rethrow;
    } finally {
      _initializing = false;
    }
  }

  static MaterialApp _wrapMaterialApp(MaterialApp app) {
    final observers = List<NavigatorObserver>.from(
      app.navigatorObservers ?? const [],
    );
    if (!observers.any((o) => o is TraceXNavigatorObserver)) {
      observers.add(TraceXNavigatorObserver());
    }

    return MaterialApp(
      key: app.key,
      scaffoldMessengerKey: app.scaffoldMessengerKey,
      home: app.home,
      routes: app.routes ?? const <String, WidgetBuilder>{},
      initialRoute: app.initialRoute,
      onGenerateRoute: app.onGenerateRoute,
      onGenerateInitialRoutes: app.onGenerateInitialRoutes,
      onUnknownRoute: app.onUnknownRoute,
      navigatorKey: app.navigatorKey,
      navigatorObservers: observers,
      builder: (context, child) {
        final originalWidget = app.builder != null
            ? app.builder!(context, child)
            : child!;

        return TraceXUserInteractionWidget(child: originalWidget);
      },
      title: app.title,
      color: app.color,
      theme: app.theme,
      darkTheme: app.darkTheme,
      themeMode: app.themeMode,
      locale: app.locale,
      localizationsDelegates: app.localizationsDelegates,
      localeListResolutionCallback: app.localeListResolutionCallback,
      localeResolutionCallback: app.localeResolutionCallback,
      supportedLocales: app.supportedLocales,
      debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
    );
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

    _connectivityMonitor?.stopListening();
    _connectivityMonitor = null;

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

  /// Records a manual breadcrumb event with a category, action, and target.
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

    // M2: Scrub error message and stack trace BEFORE deduplication and building Crash
    final scrubbedErrorMessage = DataScrubber.scrubString(errorMessage);
    final scrubbedStackTrace = DataScrubber.scrubString(stackTraceStr);

    try {
      // -----------------------------------------
      // 1. Deduplication
      // -----------------------------------------

      if (_isDuplicate(
        exceptionType: exceptionType,
        errorMessage: scrubbedErrorMessage,
        stackTrace: scrubbedStackTrace,
        timestamp: occurredAt,
      )) {
        _log('TraceX: Duplicate crash ignored.');
        _log("TraceX: Is Duplicate");

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
