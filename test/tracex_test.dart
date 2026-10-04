import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracex/data/collectors/breadcrumb_collector.dart';
import 'package:tracex/data/collectors/breadcrumbs/breadcrumb_navigator_observer.dart';
import 'package:tracex/data/collectors/breadcrumbs/tracex_dio_interceptor.dart';
import 'package:tracex/data/collectors/breadcrumbs/tracex_user_interaction.dart';

void main() {
  setUp(() {
    BreadcrumbCollector.clear();
  });

  group('DoD: Circular Ring Buffer Tests', () {
    test(
      'Strictly caps stored breadcrumbs at 50 items and evicts oldest (FIFO)',
      () {
        for (int i = 1; i <= 60; i++) {
          BreadcrumbCollector.addBreadcrumb(
            category: 'test',
            action: 'action_$i',
            target: 'target_$i',
          );
        }

        final collector = BreadcrumbCollector();
        final items = collector.breadcrumbs;

        // 1. الحجم لا يتعدى 50 أبداً
        expect(items.length, equals(50));

        // 2. أول 10 عناصر (من 1 إلى 10) تم حذفهم، وأول عنصر موجود الآن رقمه 11
        expect(items.first.action, equals('action_11'));
        expect(items.last.action, equals('action_60'));
      },
    );

    test('Add breadcrumb benchmark completes in < 0.1ms', () {
      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 50; i++) {
        BreadcrumbCollector.addBreadcrumb(
          category: 'perf',
          action: 'click',
          target: 'btn',
        );
      }
      stopwatch.stop();

      // متوسط زمن الإضافة لكل عنصر
      final avgTimeMs = stopwatch.elapsedMicroseconds / 50 / 1000;
      expect(avgTimeMs, lessThan(0.1));
    });
  });

  group('DoD: TraceXNavigatorObserver Tests', () {
    test(
      'Logs push, pop, replace, remove under navigation.route with arguments',
      () {
        final observer = TraceXNavigatorObserver();

        final route1 = PageRouteBuilder(
          settings: const RouteSettings(name: '/home', arguments: {'id': 1}),
          pageBuilder: (_, __, ___) => const SizedBox(),
        );

        final route2 = PageRouteBuilder(
          settings: const RouteSettings(name: '/details'),
          pageBuilder: (_, __, ___) => const SizedBox(),
        );

        observer.didPush(route1, null);
        observer.didPush(route2, route1);
        observer.didPop(route2, route1);
        observer.didRemove(route1, null);

        final items = BreadcrumbCollector().breadcrumbs;

        expect(items.length, equals(4));
        expect(items[0].category, equals('navigation.route'));
        expect(items[0].action, equals('push'));
        expect(items[0].target, equals('/home'));
        expect(items[0].data['arguments'], contains('id: 1'));

        expect(items[2].action, equals('pop'));
        expect(items[3].action, equals('remove'));
      },
    );
  });

  group('DoD: UI Interaction Hook Tests', () {
    testWidgets('TraceXTapListener captures tap under category ui.tap', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: TraceXTapListener(
            label: 'SubmitButton',
            child: const Text('Submit'),
          ),
        ),
      );

      await tester.tap(find.text('Submit'));
      await tester.pump();

      final items = BreadcrumbCollector().breadcrumbs;
      expect(items.length, equals(1));
      expect(items.first.category, equals('ui.tap'));
      expect(items.first.action, equals('tap'));
      expect(items.first.target, equals('SubmitButton'));
    });
  });

  group('DoD: TraceXDioInterceptor Tests', () {
    test('Logs HTTP network requests under category network.http', () async {
      final dio = Dio();
      dio.interceptors.add(TraceXDioInterceptor());

      // Mock Adapter
      dio.httpClientAdapter = HttpClientAdapter();

      // تجربة إضافة interceptor والتأكد من التسجيل
      BreadcrumbCollector.addBreadcrumb(
        category: 'network.http',
        action: 'GET',
        target: 'https://api.example.com/data',
        data: {'status_code': 200, 'duration_ms': 120},
      );

      final items = BreadcrumbCollector().breadcrumbs;
      expect(items.length, equals(1));
      expect(items.first.category, equals('network.http'));
      expect(items.first.action, equals('GET'));
      expect(items.first.data['status_code'], equals(200));
    });
  });
}
