import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:tracex_flutter/data/collectors/breadcrumb_collector.dart';

/// An automatic root widget that intercepts and records confirmed user tap interactions
/// globally across the application subtree without requiring individual widget wrapping.
class TraceXUserInteractionWidget extends StatefulWidget {
  /// The root application subtree monitored for user interactions.
  final Widget child;

  /// Creates a [TraceXUserInteractionWidget] wrapping the application [child].
  const TraceXUserInteractionWidget({super.key, required this.child});

  @override
  State<TraceXUserInteractionWidget> createState() =>
      _TraceXUserInteractionWidgetState();
}

class _TraceXUserInteractionWidgetState
    extends State<TraceXUserInteractionWidget> {
  Offset? _pointerDownPosition;

  @override
  Widget build(BuildContext context) {
    return Listener(
      // B4 Fix: Record touch-down coordinates
      onPointerDown: (PointerDownEvent event) {
        _pointerDownPosition = event.position;
      },
      // B4 Fix: Differentiate confirmed taps from scroll, flings, and drag gestures
      onPointerUp: (PointerUpEvent event) {
        try {
          if (_pointerDownPosition == null) return;
          final delta = (event.position - _pointerDownPosition!).distance;
          _pointerDownPosition = null;

          // Only process tap if movement is within standard touch slop (18.0 dp)
          if (delta <= kTouchSlop) {
            _handleInteraction(context, event.position);
          }
        } catch (_) {
          // Telemetry collection must never disrupt application flow
        }
      },
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }

  void _handleInteraction(BuildContext context, Offset position) {
    final renderBox = context.findRenderObject();
    if (renderBox is! RenderBox) return;

    final hitTestResult = BoxHitTestResult();
    if (renderBox.hitTest(hitTestResult, position: position)) {
      String? foundLabel;
      String? fallbackWidgetType;

      for (final entry in hitTestResult.path) {
        final target = entry.target;

        // 1. Text extraction from text rendering objects
        if (target is RenderParagraph) {
          final text = target.text.toPlainText().trim();
          if (text.isNotEmpty && foundLabel == null) {
            foundLabel = text.length > 30
                ? '${text.substring(0, 30)}...'
                : text;
          }
        }

        // 2. B3 Fix: Safe production-grade widget/semantics identification without debugCreator
        if (target is RenderBox) {
          final targetType = target.runtimeType.toString();

          // Inspect semantics configurations if available in release mode
          final semantics = target.toDiagnosticsNode().value;
          if (semantics is SemanticsNode) {
            final semLabel = semantics.label.trim();
            final semTooltip = semantics.tooltip.trim();
            if (semTooltip.isNotEmpty && foundLabel == null) {
              foundLabel = semTooltip;
            } else if (semLabel.isNotEmpty && foundLabel == null) {
              foundLabel = semLabel;
            }
          }

          // Identify interactive render objects (Buttons, InkWells, GestureHandlers)
          if (_isInteractiveRenderBox(targetType)) {
            fallbackWidgetType ??= _cleanRenderName(targetType);
          }
        }
      }

      // If a label or an interactive component was identified, record breadcrumb
      if (foundLabel != null || fallbackWidgetType != null) {
        final targetIdentifier = foundLabel != null
            ? (fallbackWidgetType != null
                  ? "$fallbackWidgetType('$foundLabel')"
                  : foundLabel)
            : fallbackWidgetType!;

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

  /// Identifies interactive render box patterns in Flutter release and debug modes.
  bool _isInteractiveRenderBox(String name) {
    return name.contains('Button') ||
        name.contains('Ink') ||
        name.contains('Gesture') ||
        name.contains('Semantics') ||
        name.contains('Touch') ||
        name.contains('Pointer');
  }

  String _cleanRenderName(String renderName) {
    if (renderName.startsWith('Render')) {
      return renderName.substring(6);
    }
    return renderName;
  }
}

/// B2 Fix: Deprecated wrapper retained for backward compatibility with TraceX 1.0.1.
@Deprecated('Use TraceXUserInteractionWidget for global interaction tracking')
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
