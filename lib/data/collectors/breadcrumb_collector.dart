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
        // B1: Scrub sensitive dictionary keys/values first, then sanitize primitives
        data: Map.unmodifiable(_sanitizeData(data)),
      ),
    );
  }

  /// B1: Pass raw map directly to DataScrubber first, then sanitize leaf values to JSON-safe primitives
  static Map<String, dynamic> _sanitizeData(Map<String, dynamic> raw) {
    final scrubbedMap = DataScrubber.scrubMap(raw);
    return _primitiveSanitize(scrubbedMap);
  }

  static Map<String, dynamic> _primitiveSanitize(Map<String, dynamic> map) {
    return map.map((key, value) {
      if (value == null || value is String || value is num || value is bool) {
        return MapEntry(key, value);
      } else if (value is Map<String, dynamic>) {
        return MapEntry(key, _primitiveSanitize(value));
      } else if (value is List) {
        return MapEntry(
          key,
          value.map((v) {
            if (v is Map<String, dynamic>) {
              return _primitiveSanitize(v);
            }
            return (v is num || v is bool || v == null) ? v : v.toString();
          }).toList(),
        );
      }
      return MapEntry(key, value.toString());
    });
  }

  static int get count => _buffer.length;

  static void clear() {
    _buffer.clear();
    _sequenceOrder = 0;
  }
}
