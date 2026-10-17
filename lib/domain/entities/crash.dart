import 'package:tracex_flutter/domain/entities/breadcrumb.dart';
import 'package:tracex_flutter/domain/entities/environment.dart';

/// Represents a crash incident or unhandled exception captured by TraceX.
class Crash {
  /// Optional local database identifier when buffered offline.
  final dynamic id;

  /// Project API key associated with the telemetry event.
  final String projectKey;

  /// Target platform identifier (e.g., 'flutter').
  final String platform;

  /// Target programming language identifier (e.g., 'dart').
  final String language;

  /// UTC timestamp of when the crash occurred.
  final DateTime occurredAt;

  /// Exception class or error type name.
  final String exceptionType;

  /// Human-readable error message or diagnostic summary.
  final String errorMessage;

  /// Stringified stack trace frames.
  final String stackTrace;

  /// Device and runtime environment snapshot at the time of the crash.
  final Environment environment;

  /// Breadcrumbs recorded prior to the exception.
  final List<Breadcrumb> breadcrumbs;

  /// Creates a [Crash] incident entity.
  const Crash({
    this.id,
    required this.projectKey,
    required this.platform,
    required this.language,
    required this.occurredAt,
    required this.exceptionType,
    required this.errorMessage,
    required this.stackTrace,
    required this.environment,
    required this.breadcrumbs,
  });
}
