import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/core/api_client.dart';
import 'package:shodasha_donor/core/theme.dart';
import 'package:shodasha_donor/features/home/notifications_screen.dart';
import 'package:shodasha_donor/features/orders/orders_controller.dart';

void main() {
  testWidgets(
    'notifications screen uses clean surface AppBar and shows empty state',
    (tester) async {
      final api = _FakeNotificationsApi();
      final repo = StubOrdersRepository();
      final orders = OrdersController(repo: repo);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: DonorNotificationsScreen(api: api, orders: orders),
        ),
      );
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, ShodashaTheme.surface);
      expect(appBar.elevation, 0);

      final title = tester.widget<Text>(find.text('Notifications'));
      expect(title.style?.color, ShodashaTheme.ink);

      expect(find.text('No updates yet'), findsOneWidget);
      expect(
        find.text('Order and subscription updates will appear here.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'notifications screen formats order note with 8-char uppercase ID',
    (tester) async {
      final api = _FakeNotificationsApi();
      final repo = StubOrdersRepository([
        Order(
          id: 'ord_9876543210abcdef',
          state: OrderState.placed,
          windowStart: DateTime.now(),
          itemSummary: '2 × 20L Refill',
          createdAt: DateTime(2026, 10, 31, 10, 30),
        ),
      ]);
      final orders = OrdersController(repo: repo);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: DonorNotificationsScreen(api: api, orders: orders),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Order #ORD_9876 · Placed'), findsOneWidget);
      expect(find.text('2 × 20L Refill'), findsOneWidget);
    },
  );

  testWidgets(
    'notifications screen formats subscription note with capitalized Plan title',
    (tester) async {
      final api = _FakeNotificationsApi(
        subscriptions: [
          {'status': 'active', 'qty': 1, 'next_run': '2026-11-05T09:00:00Z'},
        ],
      );
      final repo = StubOrdersRepository();
      final orders = OrdersController(repo: repo);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: DonorNotificationsScreen(api: api, orders: orders),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Plan · Active'), findsOneWidget);
      expect(find.textContaining('1 × 20L · next delivery'), findsOneWidget);
    },
  );
}

class _FakeNotificationsApi extends ApiClient {
  _FakeNotificationsApi({this.subscriptions = const []})
    : super(
        baseUrl: 'http://127.0.0.1/v1',
        deviceId: 'test-device',
        accessTokenGetter: () => 'test-token',
      );

  final List<dynamic> subscriptions;

  @override
  Future<List<dynamic>> listSubscriptions() async => subscriptions;
}
