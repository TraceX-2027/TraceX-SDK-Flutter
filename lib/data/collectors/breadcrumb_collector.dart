import 'package:tracex/data/models/breadcrumb_model.dart';

class BreadcrumbCollector {
  static final List<BreadcrumbModel> _breadcrumbs = [];
  static int _sequenceOrder = 0;

  List<BreadcrumbModel> get breadcrumbs =>
      List.unmodifiable(List<BreadcrumbModel>.from(_breadcrumbs));

  static void addBreadcrumb({
    required String category,
    required String action,
    required String target,
    Map<String, dynamic> data = const {},
  }) {
    _sequenceOrder++;

    _breadcrumbs.add(
      BreadcrumbModel(
        sequenceOrder: _sequenceOrder,
        timestamp: DateTime.now().toUtc(),
        category: category,
        action: action,
        target: target,
        data: Map.unmodifiable(Map<String, dynamic>.from(data)),
      ),
    );

    if (_breadcrumbs.length > 50) {
      _breadcrumbs.removeAt(0);
    }
  }

  static void clear() {
    _breadcrumbs.clear();
    _sequenceOrder = 0;
  }
}
