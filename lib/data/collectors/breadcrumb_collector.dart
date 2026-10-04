import 'dart:collection';
import 'package:tracex/data/models/breadcrumb_model.dart';

class BreadcrumbCollector {
  static const int maxCapacity = 50;
  static final Queue<BreadcrumbModel> _buffer = Queue<BreadcrumbModel>();
  static int _sequenceOrder = 0;

  List<BreadcrumbModel> get breadcrumbs =>
      List.unmodifiable(_buffer.toList());

  static void addBreadcrumb({
    required String category,
    required String action,
    required String target,
    Map<String, dynamic> data = const {},
  }) {
    _sequenceOrder++;

    if (_buffer.length >= maxCapacity) {
      _buffer.removeFirst();
    }

    _buffer.addLast(
      BreadcrumbModel(
        sequenceOrder: _sequenceOrder,
        timestamp: DateTime.now().toUtc(),
        category: category,
        action: action,
        target: target,
        data: Map.unmodifiable(Map<String, dynamic>.from(data)),
      ),
    );
  }

  static int get count => _buffer.length;

  static void clear() {
    _buffer.clear();
    _sequenceOrder = 0;
  }
}