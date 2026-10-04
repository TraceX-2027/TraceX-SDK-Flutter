import 'package:flutter/widgets.dart';
import 'package:tracex/data/collectors/breadcrumb_collector.dart';

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
    return Listener(
      onPointerDown: (_) {
        BreadcrumbCollector.addBreadcrumb(
          category: 'ui.tap',
          action: 'tap',
          target: label,
          data: {'widget': child.runtimeType.toString()},
        );
      },
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}
