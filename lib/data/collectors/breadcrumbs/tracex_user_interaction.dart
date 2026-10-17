import 'package:flutter/widgets.dart';
import 'package:tracex_flutter/data/collectors/breadcrumb_collector.dart';

/// Wraps [child] to capture confirmed tap gestures as breadcrumbs.
///
/// Uses [GestureDetector.onTap] instead of raw pointer tracking so that
/// scroll gestures, flings, and cancelled touches are NOT recorded,
/// preventing the 50-item ring buffer from being flooded.
class TraceXTapListener extends StatelessWidget {
  /// The widget subtree monitored for confirmed tap interactions.
  final Widget child;

  /// Semantic identifier or label associated with this UI component.
  final String label;

  /// Creates a [TraceXTapListener] wrapping the provided [child].
  const TraceXTapListener({
    super.key,
    required this.child,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        try {
          BreadcrumbCollector.addBreadcrumb(
            category: 'ui.tap',
            action: 'tap',
            target: label,
            data: {'widget': child.runtimeType.toString()},
          );
        } catch (_) {
          // Telemetry collection must never disrupt application flow
        }
      },
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}
