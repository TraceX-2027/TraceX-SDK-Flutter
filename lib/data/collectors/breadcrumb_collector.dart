import 'dart:collection';
import 'package:tracex/data/models/breadcrumb_model.dart';
import 'package:tracex/src/data_scrubber.dart';

class BreadcrumbCollector {
  static const int maxCapacity = 50;
  static final Queue<BreadcrumbModel> _buffer = Queue<BreadcrumbModel>();
  static int _sequenceOrder = 0;

  List<BreadcrumbModel> get breadcrumbs => List.unmodifiable(_buffer.toList());

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
        target: DataScrubber.scrubString(target),
        // M2 Fix & Data Scrubber: Sanitize and scrub sensitive dictionary keys/values
        data: Map.unmodifiable(_sanitizeData(data)),
      ),
    );
  }

  /// Sanitizes map values to JSON-safe primitives and scrubs sensitive data.
  static Map<String, dynamic> _sanitizeData(Map<String, dynamic> raw) {
    final primitiveMap = raw.map((key, value) {
      if (value == null || value is String || value is num || value is bool) {
        return MapEntry(key, value);
      }
      return MapEntry(key, value.toString());
    });

    return DataScrubber.scrubMap(primitiveMap);
  }

  static int get count => _buffer.length;

  static void clear() {
    _buffer.clear();
    _sequenceOrder = 0;
  }
}
