import 'package:flutter/foundation.dart';
import 'package:tracex/data/collectors/breadcrumb_collector.dart';
import 'package:tracex/domain/entities/breadcrumb.dart';
import 'package:tracex/domain/repositories/base_breadcrumb_repository.dart';

class BreadcrumbRepository extends BaseBreadcrumbRepository {
  final BreadcrumbCollector breadcrumbCollector;

  BreadcrumbRepository({required this.breadcrumbCollector});
  @override
  Future<List<Breadcrumb>> getBreadcrumbDetails() async {
    try {
      return breadcrumbCollector.breadcrumbs;
    } catch (e) {
      debugPrint('TraceX error: $e');
      rethrow;
    }
  }
}
