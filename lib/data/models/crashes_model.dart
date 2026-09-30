import 'package:tracex/data/models/breadcrumb_model.dart';
import 'package:tracex/data/models/environment_model.dart';
import 'package:tracex/domain/entities/crash.dart';

class CrashesModel extends Crash {
  CrashesModel({
    required super.projectKey,
    required super.platform,
    required super.language,
    required super.occurredAt,
    required super.exceptionType,
    required super.errorMessage,
    required super.stackTrace,
    required super.environment,
    required super.breadcrumbs,
  });

  Map<String, dynamic> toJson() {
    return {
      'project_key': projectKey,
      'platform': platform,
      'language': language,
      'occurred_at': occurredAt.toUtc().toIso8601String(),
      'exception_type': exceptionType,
      'error_message': errorMessage,
      'stack_trace': stackTrace,

      'environment': EnvironmentModel.fromEntity(environment).toJson(),

      'breadcrumbs': breadcrumbs
          .map((e) => BreadcrumbModel.fromEntity(e).toJson())
          .toList(),
    };
  }
}
