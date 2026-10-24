import 'package:flutter/widgets.dart';
import 'package:tracex_flutter/data/collectors/breadcrumb_collector.dart';

/// A [NavigatorObserver] that automatically records navigation breadcrumbs
/// for route push, pop, replace, and remove events in Flutter applications.
class TraceXNavigatorObserver extends NavigatorObserver {
  /// Creates a new [TraceXNavigatorObserver] instance.
  TraceXNavigatorObserver();

  @override
  void didPush(Route route, Route? previousRoute) {
    _logRoute('push', route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    _logRoute('pop', route);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    if (newRoute != null) {
      _logRoute('replace', newRoute);
    }
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    _logRoute('remove', route);
    super.didRemove(route, previousRoute);
  }

  void _logRoute(String action, Route route) {
    try {
      final explicitName = route.settings.name;
      final arguments = route.settings.arguments;

      if (explicitName != null &&
          explicitName.isNotEmpty &&
          explicitName != '/') {
        BreadcrumbCollector.addBreadcrumb(
          category: 'navigation',
          action: action,
          target: explicitName,
          data: {if (arguments != null) 'arguments': arguments.toString()},
        );
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        String routeName = 'Unknown';

        if (route is ModalRoute) {
          final context = route.subtreeContext;
          if (context != null && context.mounted) {
            routeName = _resolveActualScreenName(context);
          }
        }

        if (routeName == 'Unknown') {
          routeName = route.runtimeType.toString();
        }

        BreadcrumbCollector.addBreadcrumb(
          category: 'navigation',
          action: action,
          target: routeName,
          data: {if (arguments != null) 'arguments': arguments.toString()},
        );
      });
    } catch (_) {
      // Telemetry collection must never disrupt application flow
    }
  }

  String _resolveActualScreenName(BuildContext context) {
    String foundName = 'Unknown';

    final ignoredInternalPrefixes = [
      '_',
      'ModalScope',
      'Builder',
      'Semantics',
      'Theme',
      'MediaQuery',
      'Padding',
      'AnimatedBuilder',
      'RawGestureDetector',
      'Focus',
      'Actions',
      'PrimaryScrollController',
      'AnnotatedRegion',
    ];

    try {
      void visitor(Element element) {
        if (foundName != 'Unknown') return;
        final widgetType = element.widget.runtimeType.toString();
        final isInternal = ignoredInternalPrefixes.any(
          (p) => widgetType.startsWith(p),
        );
        if (!isInternal &&
            (element.widget is StatelessWidget ||
                element.widget is StatefulWidget)) {
          foundName = widgetType;
          return;
        }
        element.visitChildren(visitor);
      }

      context.visitChildElements(visitor);
    } catch (_) {}

    return foundName;
  }
}
