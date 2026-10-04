import 'package:flutter/widgets.dart';
import 'package:tracex/data/collectors/breadcrumb_collector.dart';

/// Wraps [child] to capture confirmed tap gestures as breadcrumbs.
///
/// Uses [GestureDetector.onTap] instead of raw pointer tracking so that
/// scroll gestures, flings, and cancelled touches are NOT recorded,
/// preventing the 50-item ring buffer from being flooded. (M1 Fix)
class TraceXTapListener extends StatelessWidget {
  final Widget child;
  final String label;

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
          // M1 Fix: onTap fires only on confirmed taps, not scroll gestures
          BreadcrumbCollector.addBreadcrumb(
            category: 'ui.tap',
            action: 'tap',
            target: label,
            data: {'widget': child.runtimeType.toString()},
          );
        } catch (_) {
          // M3 Fix: telemetry collection must never disrupt application flow
        }
      },
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}
