import 'package:tracex/domain/entities/breadcrumb.dart';

class BreadcrumbModel extends Breadcrumb {
  BreadcrumbModel({
    required super.sequenceOrder,
    required super.timestamp,
    required super.category,
    required super.action,
    required super.target,
    required super.data,
  });
}
