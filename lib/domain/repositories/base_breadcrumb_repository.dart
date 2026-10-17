import 'package:tracex_flutter/domain/entities/breadcrumb.dart';

abstract class BaseBreadcrumbRepository {
  Future<List<Breadcrumb>> getBreadcrumbDetails();
}
