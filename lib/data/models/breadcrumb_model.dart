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

  factory BreadcrumbModel.fromEntity(Breadcrumb breadcrumb) {
    return BreadcrumbModel(
      sequenceOrder: breadcrumb.sequenceOrder,
      timestamp: breadcrumb.timestamp,
      category: breadcrumb.category,
      action: breadcrumb.action,
      target: breadcrumb.target,
      data: breadcrumb.data,
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'sequence_order': sequenceOrder,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'category': category,
      'action': action,
      'target': target,
      'data': data,
    };
  }
}
