import 'package:tracex/domain/entities/breadcrumb.dart';
import 'package:tracex/domain/repositories/base_breadcrumb_repository.dart';

class GetBreadcrumbDetails {
  final BaseBreadcrumbRepository baseBreadcrumbRepository;

  GetBreadcrumbDetails({required this.baseBreadcrumbRepository});
  Future<List<Breadcrumb>> execute() async {
    return baseBreadcrumbRepository.getBreadcrumbDetails();
  }
}
