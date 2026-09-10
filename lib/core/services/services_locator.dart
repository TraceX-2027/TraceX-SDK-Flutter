import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:tracex/data/collectors/breadcrumb_collector.dart';
import 'package:tracex/data/collectors/environment_collector.dart';
import 'package:tracex/data/datasources/crash_remote_datasource.dart';
import 'package:tracex/data/repositories/breadcrumb_repository.dart';
import 'package:tracex/data/repositories/crash_repository.dart';
import 'package:tracex/data/repositories/environment_repository.dart';
import 'package:tracex/domain/repositories/base_breadcrumb_repository.dart';
import 'package:tracex/domain/repositories/base_environment_repository.dart';
import 'package:tracex/domain/repositories/base_crash_repository.dart';
import 'package:tracex/domain/usecases/get_breadcrumb_details.dart';
import 'package:tracex/domain/usecases/get_environment_details.dart';
import 'package:tracex/domain/usecases/send_crash_details.dart';

final sl = GetIt.asNewInstance();

class ServicesLocator {
  static final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      sendTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );
  static final EnvironmentCollector _environmentCollector =
      EnvironmentCollector();
  static final BreadcrumbCollector _breadcrumbCollector = BreadcrumbCollector();

  static void init() {
    _registerCrash();
    _registerEnvironment();
    _registerBreadcrumt();
  }

  static void _registerCrash() {
    sl.registerLazySingleton<BaseCrashRemoteDatasources>(
      () => CrashRemoteDatasources(dio: _dio),
    );

    sl.registerLazySingleton<BaseCrashRepository>(
      () => CrashRepository(baseCrashRemoteDatasorces: sl()),
    );

    sl.registerLazySingleton<SentCrashDetils>(
      () => SentCrashDetils(baseCrashRepository: sl()),
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

  static void _registerBreadcrumt() {
    sl.registerLazySingleton<BaseBreadcrumbRepository>(
      () => BreadcrumbRepository(breadcrumbCollector: _breadcrumbCollector),
    );

    sl.registerLazySingleton<GetBreadcrumbDetails>(
      () => GetBreadcrumbDetails(baseBreadcrumbRepository: sl()),
    );
  }
}
