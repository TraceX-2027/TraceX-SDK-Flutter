/// Represents a single chronological diagnostic breadcrumb leading up to an incident.
class Breadcrumb {
  /// Sequential index of the breadcrumb in the active session.
  final int sequenceOrder;

  /// UTC timestamp of when the event occurred.
  final DateTime timestamp;

  /// Breadcrumb category (e.g., 'navigation', 'network.http', 'ui.tap').
  final String category;

  /// Specific action triggered (e.g., 'push', 'GET', 'tap').
  final String action;

  /// Target component, endpoint, or route affected.
  final String target;

  /// Key-value metadata contextualizing the event.
  final Map<String, dynamic> data;

  /// Creates a immutable [Breadcrumb] entity.
  const Breadcrumb({
    required this.sequenceOrder,
    required this.timestamp,
    required this.category,
    required this.action,
    required this.target,
    required this.data,
  });
}
