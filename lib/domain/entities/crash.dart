import 'package:tracex/domain/entities/breadcrumb.dart';
import 'package:tracex/domain/entities/environment.dart';

class Crash {
  final String projectKey;
  final String platform;
  final String language;
  final DateTime occurredAt;
  final String exceptionType;
  final String errorMessage;
  final String stackTrace;
  final Environment environment;
  final List<Breadcrumb> breadcrumbs;

  const Crash({
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
