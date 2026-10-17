import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:tracex_flutter/core/utils/api_const.dart';
import 'package:tracex_flutter/data/collectors/breadcrumb_collector.dart';
import 'package:tracex_flutter/data/collectors/environment_collector.dart';
import 'package:tracex_flutter/data/datasources/crash_offline_datasource.dart';
import 'package:tracex_flutter/data/datasources/crash_remote_datasource.dart';
import 'package:tracex_flutter/data/repositories/breadcrumb_repository.dart';
import 'package:tracex_flutter/data/repositories/crash_offline_repository.dart';
import 'package:tracex_flutter/data/repositories/crash_repository.dart';
import 'package:tracex_flutter/data/repositories/environment_repository.dart';
import 'package:tracex_flutter/domain/repositories/base_breadcrumb_repository.dart';
import 'package:tracex_flutter/domain/repositories/base_crash_offline_repository.dart';
import 'package:tracex_flutter/domain/repositories/base_crash_repository.dart';
import 'package:tracex_flutter/domain/repositories/base_environment_repository.dart';
import 'package:tracex_flutter/domain/usecases/get_breadcrumb_details.dart';
import 'package:tracex_flutter/domain/usecases/get_environment_details.dart';
import 'package:tracex_flutter/domain/usecases/save_offline_crash.dart';
import 'package:tracex_flutter/domain/usecases/send_batch_crash_details.dart';
import 'package:tracex_flutter/domain/usecases/send_crash_details.dart';

/// Service locator container instance used for TraceX dependency injection.
final sl = GetIt.asNewInstance();

/// Dependency injection and service registry for TraceX core services, datasources, and repositories.
class ServicesLocator {
  ServicesLocator._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      sendTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'TraceX-Flutter-SDK/1.0.1',
        'Connection': 'keep-alive',
      },
    ),
  );

  static final EnvironmentCollector _environmentCollector =
      EnvironmentCollector();

  static final BreadcrumbCollector _breadcrumbCollector = BreadcrumbCollector();

  static bool _initialized = false;

  /// Internal [Dio] HTTP client instance.
  @visibleForTesting
  static Dio get dio => _dio;

  /// Whether services have been initialized.
  @visibleForTesting
  static bool get isInitialized => _initialized;

  /// Initializes all service singletons and registers them with [sl].
  static Future<void> init({String? endpoint, String? fallbackEndpoint}) async {
    if (_initialized) {
      return;
    }

    try {
      var targetUrl = (endpoint != null && endpoint.trim().isNotEmpty)
          ? endpoint.trim()
          : ApiConst.baseUrl;
      if (!targetUrl.endsWith('/')) {
        targetUrl = '$targetUrl/';
      }
      _dio.options.baseUrl = targetUrl;

      final isEdgeTarget =
          endpoint == null ||
          targetUrl == ApiConst.edgeBaseUrl ||
          targetUrl.contains('workers.dev');
      final fallback = isEdgeTarget
          ? (fallbackEndpoint ?? ApiConst.originCrashUrl)
          : null;

      _registerCrash(fallbackUrl: fallback);

      await _registerOfflineCrash();

      _registerEnvironment();

      _registerBreadcrumbs();

      _initialized = true;
    } catch (e) {
      await sl.reset();
      _initialized = false;
      rethrow;
    }
  }

  static void _registerCrash({String? fallbackUrl}) {
    sl.registerLazySingleton<BaseCrashRemoteDatasource>(
      () => CrashRemoteDatasource(dio: _dio, fallbackUrl: fallbackUrl),
    );

    sl.registerLazySingleton<BaseCrashRepository>(
      () => CrashRepository(baseCrashRemoteDatasources: sl()),
    );

    sl.registerLazySingleton<SendCrashDetails>(
      () => SendCrashDetails(baseCrashRepository: sl()),
    );
    sl.registerLazySingleton<SendBatchCrashDetails>(
      () => SendBatchCrashDetails(baseCrashRepository: sl()),
    );
  }

  static Future<void> _registerOfflineCrash() async {
    final CrashOfflineDatasource crashOfflineDatasource =
        CrashOfflineDatasource();

    await crashOfflineDatasource.init();

    sl.registerLazySingleton<BaseCrashOfflineDatasource>(
      () => crashOfflineDatasource,
    );

    sl.registerLazySingleton<BaseCrashOfflineRepository>(
      () => CrashOfflineRepository(datasource: sl()),
    );

    sl.registerLazySingleton<CrashOffline>(
      () => CrashOffline(baseCrashOfflineRepository: sl()),
    );
  }

  static void _registerEnvironment() {
    sl.registerLazySingleton<BaseEnvironmentRepository>(
      () => EnvironmentRepository(environmentCollector: _environmentCollector),
    );

    sl.registerLazySingleton<GetEnvironmentDetails>(
      () => GetEnvironmentDetails(baseEnvironmentCollector: sl()),
    );
  }

  static void _registerBreadcrumbs() {
    sl.registerLazySingleton<BaseBreadcrumbRepository>(
      () => BreadcrumbRepository(breadcrumbCollector: _breadcrumbCollector),
    );

    sl.registerLazySingleton<GetBreadcrumbDetails>(
      () => GetBreadcrumbDetails(baseBreadcrumbRepository: sl()),
    );
  }

  /// Resets all registered services and singletons in the service locator.
  static Future<void> reset() async {
    BreadcrumbCollector.clear();
    await sl.reset();
    _initialized = false;
  }
}
