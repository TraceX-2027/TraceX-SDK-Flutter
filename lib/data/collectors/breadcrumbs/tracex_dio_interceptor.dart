import 'package:dio/dio.dart';
import 'package:tracex/data/collectors/breadcrumb_collector.dart';

class TraceXDioInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['tracex_start_time'] = DateTime.now().millisecondsSinceEpoch;
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final startTime =
        response.requestOptions.extra['tracex_start_time'] as int?;
    final durationMs = startTime != null
        ? DateTime.now().millisecondsSinceEpoch - startTime
        : 0;

    BreadcrumbCollector.addBreadcrumb(
      category: 'network.http',
      action: response.requestOptions.method,
      target: response.requestOptions.uri.toString(),
      data: {
        'status_code': response.statusCode ?? 200,
        'duration_ms': durationMs,
      },
    );

    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final startTime = err.requestOptions.extra['tracex_start_time'] as int?;
    final durationMs = startTime != null
        ? DateTime.now().millisecondsSinceEpoch - startTime
        : 0;

    BreadcrumbCollector.addBreadcrumb(
      category: 'network.http',
      action: err.requestOptions.method,
      target: err.requestOptions.uri.toString(),
      data: {
        'status_code': err.response?.statusCode ?? 0,
        'duration_ms': durationMs,
        'error': err.message ?? err.type.toString(),
      },
    );

    super.onError(err, handler);
  }
}
