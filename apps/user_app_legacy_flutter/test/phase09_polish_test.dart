// Phase 9 polish tests (ADR-091): skeletons on tracking/subs/support +
// 200ms tracker-step transition with reduced-motion static fallback.
// Run: flutter test test/phase09_polish_test.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/features/orders/orders_controller.dart';
import 'package:shodasha_app/features/orders/tracking_screen.dart';
import 'package:shodasha_app/features/subscriptions/subscription_screen.dart';
import 'package:shodasha_app/features/support/support_screen.dart';

/// Never-resolving API: controllers stay in `loading` with empty items.
class _HangingApi extends ApiClient {
  _HangingApi() : super(baseUrl: 'https://example.test');

  @override
  Future<List<dynamic>> listSubscriptions() =>
      Completer<List<dynamic>>().future;

  @override
  Future<Map<String, dynamic>> billingDues() =>
      Completer<Map<String, dynamic>>().future;

  @override
  Future<List<dynamic>> listComplaints() =>
      Completer<List<dynamic>>().future;
}

class _HangingOrdersRepo implements OrdersRepository {
  @override
  Future<OrdersPage> fetchOrders({String? cursor}) =>
      Completer<OrdersPage>().future;

  @override
  Future<Order> fetchOrder(String id) => Completer<Order>().future;

  @override
  Future<Order> cancelOrder(String id, String reasonCode) =>
      Completer<Order>().future;

  @override
  Future<Order> rescheduleOrder(String id, DateTime windowStart) =>
      Completer<Order>().future;

  @override
  Future<Order> submitRating(String id, int stars) =>
      Completer<Order>().future;
}

void main() {
  group('Phase 9 §9.1 skeletons (no bare spinners on first load)', () {
    testWidgets('tracking shows tracker skeleton while loading', (tester) async {
      final c = OrdersController(repo: _HangingOrdersRepo());
      unawaited(c.load());
      await tester.pumpWidget(
        MaterialApp(home: TrackingScreen(controller: c, orderId: 'missing')),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // Skeleton boxes render (header + tracker + bill).
      expect(find.byType(Container), findsWidgets);
      c.stopTracking();
      c.dispose();
    });

    testWidgets('subs shows list skeleton while loading', (tester) async {
      final c = SubscriptionController(api: _HangingApi());
      await tester.pumpWidget(
        MaterialApp(home: SubscriptionScreen(controller: c)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(Container), findsWidgets);
      c.dispose();
    });

    testWidgets('support complaints show skeleton while loading', (tester) async {
      final c = SupportController(api: _HangingApi());
      await tester.pumpWidget(
        MaterialApp(home: SupportScreen(controller: c)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      c.dispose();
    });
  });

  group('Phase 9 §9.1 tracker-step transition (200ms, gated)', () {
    testWidgets('dot fill pops + check fades on step change', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: FourStepTracker(step: 0)),
        ),
      );
      await tester.pump();
      // Step up: the newly filled dot scales 0.8 → 1.0 mid-flight.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: FourStepTracker(step: 1)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final midFlight = tester.widgetList<AnimatedScale>(find.byType(AnimatedScale));
      expect(midFlight.any((w) => w.scale != 1.0), isTrue);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widgetList<AnimatedScale>(find.byType(AnimatedScale)).every((w) => w.scale == 1.0 || w.scale == 0.8),
        isTrue,
      );
    });

    testWidgets('reduced motion renders static dots (no implicit animation)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(body: FourStepTracker(step: 2)),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(AnimatedScale), findsNothing);
      expect(find.byType(AnimatedOpacity), findsNothing);
      // State still reads: 3 filled checks render.
      expect(find.byIcon(Icons.check), findsNWidgets(3));
    });
  });
}
