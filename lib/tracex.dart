import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'package:tracex/core/services/services_locator.dart';
import 'package:tracex/domain/entities/crash.dart';
import 'package:tracex/domain/repositories/base_breadcrumb_repository.dart';
import 'package:tracex/domain/repositories/base_crash_repository.dart';
import 'package:tracex/domain/repositories/base_environment_repository.dart';
import 'package:tracex/domain/usecases/get_breadcrumb_details.dart';
import 'package:tracex/domain/usecases/get_environment_details.dart';
import 'package:tracex/domain/usecases/sent_crash_detiles.dart';

class TraceX {
  TraceX._();

  // ============================================================
  // Configuration
  // ============================================================

  static const String _platform = 'flutter';
  static const String _language = 'dart';

  // ============================================================
  // State
  // ============================================================

  static String? _projectKey;

  static SentCrashDetiles? _sendCrashDetails;
  static GetEnvironmentDetails? _getEnvironmentDetails;
  static GetBreadcrumbDetails? _getBreadcrumbDetails;

  static bool _initialized = false;
  static bool _initializing = false;

  // ============================================================
  // Previous Handlers
  // ============================================================

  static FlutterExceptionHandler? _previousFlutterErrorHandler;

  static bool Function(Object error, StackTrace stack)?
  _previousPlatformErrorHandler;

  // ============================================================
  // Getters
  // ============================================================

  static bool get isInitialized => _initialized;

  static String? get projectKey => _projectKey;

  // ============================================================
  // Initialize
  // ============================================================

  static Future<void> initialize({required String projectKey}) async {
    if (_initialized || _initializing) {
      return;
    }

    _initializing = true;

    try {
      if (projectKey.trim().isEmpty) {
        throw ArgumentError('TraceX projectKey cannot be empty.');
      }

      _projectKey = projectKey;

      // ----------------------------------------------------------
      // Dependency Injection
      // ----------------------------------------------------------

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

      // ----------------------------------------------------------
      // Initialize Environment Collector
      // ----------------------------------------------------------

      await _getEnvironmentDetails!.initialize();

      // ----------------------------------------------------------
      // Save Existing Error Handlers
      // ----------------------------------------------------------

      _previousFlutterErrorHandler = FlutterError.onError;

      _previousPlatformErrorHandler = PlatformDispatcher.instance.onError;

      // ----------------------------------------------------------
      // Register Flutter Error Handler
      // ----------------------------------------------------------

      FlutterError.onError = (FlutterErrorDetails details) {
        // Keep Flutter's default behavior in debug mode.
        if (kDebugMode) {
          FlutterError.dumpErrorToConsole(details);
        }

        // Send to TraceX
        unawaited(
          _captureException(
            details.exception,
            details.stack ?? StackTrace.current,
          ),
        );

        // Call previous handler if one exists.
        _previousFlutterErrorHandler?.call(details);
      };

      // ----------------------------------------------------------
      // Register Async / Platform Error Handler
      // ----------------------------------------------------------

      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        // Send to TraceX
        unawaited(_captureException(error, stack));

        // Preserve previous handler behavior.
        final previousHandler = _previousPlatformErrorHandler;

        if (previousHandler != null) {
          return previousHandler(error, stack);
        }

        // TraceX handled the error.
        return true;
      };

      _initialized = true;

      debugPrint('TraceX initialized');
    } catch (e, stack) {
      debugPrint('TraceX initialization failed: $e');

      debugPrint('$stack');
    } finally {
      _initializing = false;
    }
  }

  // ============================================================
  // Capture Exception
  // ============================================================

  static Future<void> _captureException(Object error, StackTrace stack) async {
    try {
      // ----------------------------------------------------------
      // Check Initialization
      // ----------------------------------------------------------

      if (!_initialized) {
        debugPrint(
          'TraceX is not initialized. '
          'Call TraceX.initialize() first.',
        );

        return;
      }

      final sendCrashDetails = _sendCrashDetails;

      final getEnvironmentDetails = _getEnvironmentDetails;
      final getBreadcrumbDetails = _getBreadcrumbDetails;
      final projectKey = _projectKey;

      if (sendCrashDetails == null ||
          getEnvironmentDetails == null ||
          projectKey == null) {
        debugPrint('TraceX internal state is invalid.');

        return;
      }

      // ----------------------------------------------------------
      // Collect Environment
      // ----------------------------------------------------------

      final environment = await getEnvironmentDetails.execute();
      final breadcrumbs = await getBreadcrumbDetails!.execute();

      // ----------------------------------------------------------
      // Build Crash
      // ----------------------------------------------------------

      final crash = Crash(
        projectKey: projectKey,
        platform: _platform,
        language: _language,
        timestamp: DateTime.now().toUtc(),
        exceptionType: error.runtimeType.toString(),
        errorMessage: error.toString(),
        stackTrace: stack.toString(),
        environment: environment,

        // Breadcrumbs will be added later.
        breadcrumbs: breadcrumbs,
      );

      // ----------------------------------------------------------
      // Send Crash
      // ----------------------------------------------------------

      await sendCrashDetails.execute(crash);

      debugPrint('TraceX: Crash sent successfully');
    } catch (e, stack) {
      // TraceX must NEVER crash the host application.

      debugPrint('TraceX failed to capture/send crash: $e');

      debugPrint('$stack');
    }
  }
}
