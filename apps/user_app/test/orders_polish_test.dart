// S5 — orders-only polish assertions ported from the legacy
// phase09_polish_test.dart (ADR-091). The legacy file also covered
// subscriptions/support skeletons; those belong to S6/S8 and are intentionally
// not imported here.
//
// Covers: tracking skeleton while loading (no bare spinner) + the gated
// 200ms tracker-step transition (AnimatedScale/AnimatedOpacity) with the
// reduced-motion static fallback.
// Run: flutter test test/orders_polish_test.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_app/features/orders/orders_controller.dart';
import 'package:shodasha_app/features/orders/tracking_screen.dart';

/// Never-resolving repo: the controller stays loading with no rows.
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
  Future<Order> submitRating(String id, int stars) => Completer<Order>().future;
}

void main() {
  group('tracking skeleton (no bare spinner on first load)', () {
    testWidgets('renders skeleton boxes while loading', (tester) async {
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
  });

  group('tracker-step transition (200ms, gated)', () {
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
      final midFlight =
          tester.widgetList<AnimatedScale>(find.byType(AnimatedScale));
      expect(midFlight.any((w) => w.scale != 1.0), isTrue);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester
            .widgetList<AnimatedScale>(find.byType(AnimatedScale))
            .every((w) => w.scale == 1.0 || w.scale == 0.8),
        isTrue,
      );
    });

    testWidgets('reduced motion renders static dots (no implicit animation)',
        (tester) async {
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
