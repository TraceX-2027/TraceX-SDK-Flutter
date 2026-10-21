import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:tracex_flutter/data/collectors/breadcrumb_collector.dart';

/// An automatic root widget that intercepts and records confirmed user tap interactions
/// globally across the application subtree without requiring individual widget wrapping.
class TraceXUserInteractionWidget extends StatelessWidget {
  /// The root application subtree monitored for user interactions.
  final Widget child;

  /// Creates a [TraceXUserInteractionWidget] wrapping the application [child].
  const TraceXUserInteractionWidget({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerUp: (PointerUpEvent event) {
        try {
          _handleInteraction(context, event.position);
        } catch (_) {
          // Telemetry collection must never disrupt application flow
        }
      },
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }

  void _handleInteraction(BuildContext context, Offset position) {
    final renderBox = context.findRenderObject();
    if (renderBox is! RenderBox) return;

    final hitTestResult = BoxHitTestResult();
    if (renderBox.hitTest(hitTestResult, position: position)) {
      String? foundWidgetName;
      String? foundLabel;

      for (final entry in hitTestResult.path) {
        final target = entry.target;

        if (target is RenderParagraph) {
          final text = target.text.toPlainText().trim();
          if (text.isNotEmpty && foundLabel == null) {
            foundLabel = text.length > 30
                ? '${text.substring(0, 30)}...'
                : text;
          }
        }

        if (target is RenderBox) {
          final creator = target.debugCreator;
          if (creator is DebugCreator) {
            final element = creator.element;
            final widgetName = element.widget.runtimeType.toString();

            if (_isInteractiveWidget(widgetName)) {
              foundWidgetName ??= widgetName;
            }
          }
        }
      }

      if (foundWidgetName != null || foundLabel != null) {
        final targetIdentifier = foundLabel != null
            ? (foundWidgetName != null
                  ? "$foundWidgetName('$foundLabel')"
                  : foundLabel)
            : foundWidgetName!;

        BreadcrumbCollector.addBreadcrumb(
          category: 'ui.tap',
          action: 'tap',
          target: targetIdentifier,
          data: {
            'position_x': position.dx.round(),
            'position_y': position.dy.round(),
          },
        );
      }
    }
  }

  bool _isInteractiveWidget(String name) {
    return name.contains('Button') ||
        name.contains('InkWell') ||
        name.contains('GestureDetector') ||
        name.contains('ListTile') ||
        name.contains('Switch') ||
        name.contains('Checkbox') ||
        name.contains('Radio') ||
        name.contains('IconButton') ||
        name.contains('Chip');
  }
}
