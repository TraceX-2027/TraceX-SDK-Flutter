import 'package:flutter/widgets.dart';
import 'package:tracex/data/collectors/breadcrumb_collector.dart';

class TraceXNavigatorObserver extends NavigatorObserver {
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
      final routeName = route.settings.name ?? route.runtimeType.toString();
      final arguments = route.settings.arguments;

      // N1 Fix: category is 'navigation' (not 'navigation.route') per API spec §3.1
      BreadcrumbCollector.addBreadcrumb(
        category: 'navigation',
        action: action,
        target: routeName,
        data: {if (arguments != null) 'arguments': arguments.toString()},
      );
    } catch (_) {
      // M3 Fix: telemetry collection must never disrupt application flow
    }
  }
}
