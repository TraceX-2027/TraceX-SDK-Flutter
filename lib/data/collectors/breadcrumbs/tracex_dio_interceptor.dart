import 'package:dio/dio.dart';
import 'package:tracex_flutter/data/collectors/breadcrumb_collector.dart';

/// A Dio [Interceptor] that automatically intercepts HTTP requests, responses,
/// and errors to record diagnostic network breadcrumbs.
class TraceXDioInterceptor extends Interceptor {
  /// Creates a new [TraceXDioInterceptor] instance.
  TraceXDioInterceptor();

  /// Paths belonging to the TraceX SDK itself.
  /// Requests to these paths will NOT generate breadcrumbs to avoid
  /// self-telemetry loops polluting the ring buffer.
  static const _excludedPaths = ['/crashes', '/api/v1/crashes'];

  bool _isTracexIngestion(Uri uri) {
    return _excludedPaths.any((p) => uri.path.endsWith(p));
  }

  /// Sanitizes a URI to a safe target string and truncates to max 255
  /// characters to match the PostgreSQL VARCHAR(255) column limit.
  String _resolveTarget(Uri uri) {
    final path = uri.path.isNotEmpty ? uri.path : uri.toString();
    return path.length > 255 ? path.substring(0, 255) : path;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['tracex_start_time'] = DateTime.now().millisecondsSinceEpoch;
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    try {
      if (!_isTracexIngestion(response.requestOptions.uri)) {
        final startTime =
            response.requestOptions.extra['tracex_start_time'] as int?;
        final durationMs = startTime != null
            ? DateTime.now().millisecondsSinceEpoch - startTime
            : 0;

        BreadcrumbCollector.addBreadcrumb(
          category: 'network.http',
          action: response.requestOptions.method,
          target: _resolveTarget(response.requestOptions.uri),
          data: {
            'status_code': response.statusCode ?? 200,
            'duration_ms': durationMs,
          },
        );
      }
    } catch (_) {
      // Telemetry collection must never disrupt application flow
    }
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    try {
      if (!_isTracexIngestion(err.requestOptions.uri)) {
        final startTime = err.requestOptions.extra['tracex_start_time'] as int?;
        final durationMs = startTime != null
            ? DateTime.now().millisecondsSinceEpoch - startTime
            : 0;

        BreadcrumbCollector.addBreadcrumb(
          category: 'network.http',
          action: err.requestOptions.method,
          target: _resolveTarget(err.requestOptions.uri),
          data: {
            'status_code': err.response?.statusCode ?? 0,
            'duration_ms': durationMs,
            'error': err.message ?? err.type.toString(),
          },
        );
      }
    } catch (_) {
      // Telemetry collection must never disrupt application flow
    }
    super.onError(err, handler);
  }
}
