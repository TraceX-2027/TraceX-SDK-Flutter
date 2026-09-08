import 'package:flutter/cupertino.dart';
import 'package:tracex/data/collectors/breadcrumb_collector.dart';

class TraceXNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route route, Route? previousRoute) {
    BreadcrumbCollector.addBreadcrumb(
      category: 'navigation',
      action: 'push',
      target: route.settings.name ?? route.runtimeType.toString(),
    );

    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    BreadcrumbCollector.addBreadcrumb(
      category: 'navigation',
      action: 'pop',
      target: route.settings.name ?? route.runtimeType.toString(),
    );

    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    BreadcrumbCollector.addBreadcrumb(
      category: 'navigation',
      action: 'replace',
      target:
          newRoute?.settings.name ??
          newRoute?.runtimeType.toString() ??
          'unknown',
    );

    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
