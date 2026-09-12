import 'package:tracex/domain/entities/breadcrumb.dart';

abstract class BaseBreadcrumbRepository {
  Future<List<Breadcrumb>> getBreadcrumbDetails();
}
