class Breadcrumb {
  final int sequenceOrder;
  final DateTime timestamp;
  final String category;
  final String action;
  final String target;
  final Map<String, dynamic> data;

  const Breadcrumb({
    required this.sequenceOrder,
    required this.timestamp,
    required this.category,
    required this.action,
    required this.target,
    required this.data,
  });

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
