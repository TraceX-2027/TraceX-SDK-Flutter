import 'package:tracex/domain/entities/crash.dart';

class CrashesModel extends Crash {
  CrashesModel({
    required super.projectKey,
    required super.platform,
    required super.language,
    required super.timestamp,
    required super.exceptionType,
    required super.errorMessage,
    required super.stackTrace,
    required super.environment,
    required super.breadcrumbs,
  });
}
