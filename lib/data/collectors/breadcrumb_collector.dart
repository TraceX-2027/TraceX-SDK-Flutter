import 'dart:collection';
import 'package:tracex_flutter/data/models/breadcrumb_model.dart';
import 'package:tracex_flutter/src/data_scrubber.dart';

/// Collector that manages an in-memory 50-item ring buffer for diagnostic breadcrumb telemetry.
class BreadcrumbCollector {
  /// Default constructor for [BreadcrumbCollector].
  BreadcrumbCollector();

  /// Maximum number of breadcrumb entries retained before oldest entries are evicted.
  static const int maxCapacity = 50;
  static final Queue<BreadcrumbModel> _buffer = Queue<BreadcrumbModel>();
  static int _sequenceOrder = 0;

  /// Current snapshot of buffered breadcrumb entries in chronological order.
  List<BreadcrumbModel> get breadcrumbs => List.unmodifiable(_buffer.toList());

  /// Records a new breadcrumb event, evicting the oldest record if buffer exceeds [maxCapacity].
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
        data: Map.unmodifiable(_sanitizeData(data)),
      ),
    );
  }

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

  /// Number of breadcrumbs currently stored in the ring buffer.
  static int get count => _buffer.length;

  /// Clears all buffered breadcrumbs and resets the sequence counter.
  static void clear() {
    _buffer.clear();
    _sequenceOrder = 0;
  }
}
