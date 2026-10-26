// F4 — Order state unit tests (visibility matrix, paise formatting, cancel
// reasons, reschedule slots, client search, poll backoff, rating-once).
// Run: flutter test test/order_states_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_app/features/orders/orders_controller.dart';
import 'package:shodasha_app/features/orders/tracking_screen.dart';

Order _order({
  String id = 'o1',
  OrderState state = OrderState.placed,
  bool rated = false,
  int totalPaise = 5600,
  String item = '2 jars',
  String address = 'Sector 21',
}) {
  return Order(
    id: id,
    state: state,
    windowStart: DateTime(2026, 9, 30, 9, 0),
    windowEnd: DateTime(2026, 9, 30, 9, 30),
    itemSummary: item,
    addressLabel: address,
    totalPaise: totalPaise,
    rated: rated,
  );
}

void main() {
  group('formatRupees (paise ints, 2dp only when needed)', () {
    test('whole rupees have no decimals', () {
      expect(formatRupees(2800), '\u20B928');
      expect(formatRupees(5600), '\u20B956');
      expect(formatRupees(0), '\u20B90');
    });

    test('paise shows 2dp', () {
      expect(formatRupees(2850), '\u20B928.50');
      expect(formatRupees(5), '\u20B90.05');
    });
  });

  group('visibility matrix (§4.4 + flows 3/5)', () {
    test('pre-dispatch → Cancel + Reschedule', () {
      for (final s in [
        OrderState.placed,
        OrderState.accepted,
        OrderState.picked,
        OrderState.packed,
        OrderState.assigned,
      ]) {
        final o = _order(state: s);
        expect(o.canCancel, isTrue, reason: s.name);
        expect(o.canReschedule, isTrue, reason: s.name);
        expect(o.showWhatsAppOnly, isFalse, reason: s.name);
      }
    });

    test('dispatched → WhatsApp CTA only', () {
      final o = _order(state: OrderState.dispatched);
      expect(o.canCancel, isFalse);
      expect(o.canReschedule, isFalse);
      expect(o.showWhatsAppOnly, isTrue);
    });

    test('delivered → help row + rate once', () {
      final fresh = _order(state: OrderState.delivered);
      expect(fresh.showHelpRow, isTrue);
      expect(fresh.canRate, isTrue);
      final rated = _order(state: OrderState.delivered, rated: true);
      expect(rated.canRate, isFalse);
      expect(rated.showHelpRow, isTrue);
    });

    test('cancelled → none', () {
      final o = _order(state: OrderState.cancelled);
      expect(o.canCancel, isFalse);
      expect(o.canReschedule, isFalse);
      expect(o.showWhatsAppOnly, isFalse);
      expect(o.canRate, isFalse);
      expect(o.showNoActions, isTrue);
    });
  });

  group('trackerStep (4-step solid dots)', () {
    test('maps canonical states to 0..3, terminal to -1', () {
      expect(trackerStep(OrderState.placed), 0);
      expect(trackerStep(OrderState.accepted), 0);
      expect(trackerStep(OrderState.picked), 1);
      expect(trackerStep(OrderState.packed), 1);
      expect(trackerStep(OrderState.assigned), 1);
      expect(trackerStep(OrderState.dispatched), 2);
      expect(trackerStep(OrderState.delivered), 3);
      expect(trackerStep(OrderState.cancelled), -1);
      expect(trackerStep(OrderState.failed), -1);
    });
  });

  group('cancel reasons (dropdown codes)', () {
    test('five codes round-trip', () {
      expect(CancelReason.values.length, 5);
      for (final r in CancelReason.values) {
        expect(CancelReason.fromCode(r.code), r);
      }
    });

    test('unknown code falls back to other', () {
      expect(CancelReason.fromCode('nope'), CancelReason.other);
    });
  });

  group('reschedule slots (next-day 30-min 8–20, 014 all-days)', () {
    test('24 half-hour slots inside 8–20', () {
      // 2026-09-29 is a Tuesday → next day Wed, no skip.
      final slots = nextServiceSlots(from: DateTime(2026, 9, 29, 12));
      expect(slots.length, 24);
      expect(slots.first.start.hour, 8);
      expect(slots.first.start.minute, 0);
      expect(slots.last.start.hour, 19);
      expect(slots.last.start.minute, 30);
      for (var i = 1; i < slots.length; i++) {
        expect(
          slots[i].start.difference(slots[i - 1].start),
          const Duration(minutes: 30),
        );
      }
    });

    test('no Sunday skip (014 all-days water)', () {
      // 2026-10-03 is a Saturday → next day Sun stays serviceable.
      final slots = nextServiceSlots(from: DateTime(2026, 10, 3, 12));
      expect(slots.first.start.weekday, DateTime.sunday);
      expect(slots.first.start.day, 4);
    });
  });

  group('client-side search filter (no server q)', () {
    test('filters by id / address / item', () async {
      final c = OrdersController(
        repo: StubOrdersRepository([
          _order(id: 'A100', item: '2 jars', address: 'Sector 21'),
          _order(id: 'B200', item: '5 jars', address: 'Gomti Nagar'),
        ]),
      );
      await c.load(); // search filters the LOADED list (screen loads first)
      c.setQuery('');
      expect(c.filteredOrders.length, 2);
      c.setQuery('a100');
      expect(c.filteredOrders.map((o) => o.id), ['A100']);
      c.setQuery('gomti');
      expect(c.filteredOrders.map((o) => o.id), ['B200']);
      c.setQuery('5 jars');
      expect(c.filteredOrders.map((o) => o.id), ['B200']);
      c.setQuery('zzz');
      expect(c.filteredOrders, isEmpty);
      c.dispose();
    });
  });

  group('poll backoff (60s base, max 300s)', () {
    test('doubles on error, caps at 300, resets on success', () {
      final c = OrdersController(repo: StubOrdersRepository());
      expect(c.pollSeconds, 60);
      c.simulatePollError();
      expect(c.pollSeconds, 120);
      c.simulatePollError();
      expect(c.pollSeconds, 240);
      c.simulatePollError();
      expect(c.pollSeconds, 300);
      c.simulatePollError();
      expect(c.pollSeconds, 300);
      c.simulatePollSuccess();
      expect(c.pollSeconds, 60);
      c.dispose();
    });
  });

  group('rating once + auto-popup', () {
    test('shouldAutoPrompt fires once per delivered view', () async {
      final repo = StubOrdersRepository([
        _order(id: 'D1', state: OrderState.delivered),
      ]);
      final c = OrdersController(repo: repo);
      await c.load();
      final o = c.findById('D1')!;
      expect(c.shouldAutoPrompt(o), isTrue);
      c.markRatingPrompted('D1');
      expect(c.shouldAutoPrompt(o), isFalse);
      c.dispose();
    });

    test('rate succeeds once, second rate fails', () async {
      final repo = StubOrdersRepository([
        _order(id: 'D2', state: OrderState.delivered),
      ]);
      final c = OrdersController(repo: repo);
      await c.load();
      expect(await c.rate('D2', 5), isTrue);
      expect(c.findById('D2')!.canRate, isFalse);
      expect(await c.rate('D2', 4), isFalse);
      c.dispose();
    });

    test('cancel pre-dispatch ok, post-dispatch blocked', () async {
      final repo = StubOrdersRepository([
        _order(id: 'P1', state: OrderState.placed),
        _order(id: 'X1', state: OrderState.dispatched),
      ]);
      final c = OrdersController(repo: repo);
      await c.load();
      expect(await c.cancel('P1', 'changed_mind'), isTrue);
      expect(c.findById('P1')!.state, OrderState.cancelled);
      expect(await c.cancel('X1', 'changed_mind'), isFalse);
      c.dispose();
    });
  });

  group('payment badge — tracking header UPI/COD + Paid/due (015)', () {
    testWidgets('header shows UPI Paid + tappable bill note → bill Mode line', (
      tester,
    ) async {
      final order = Order(
        id: 'T1',
        state: OrderState.placed,
        windowStart: DateTime(2026, 9, 30, 9, 0),
        windowEnd: DateTime(2026, 9, 30, 9, 30),
        itemSummary: '2 jars',
        addressLabel: 'Sector 21',
        totalPaise: 5600,
        paymentsPaise: 2000,
        paymentMode: 'upi',
        paymentStatus: 'paid_upi',
      );
      final c = OrdersController(repo: StubOrdersRepository([order]));
      await c.load();
      await tester.pumpWidget(
        MaterialApp(
          home: TrackingScreen(controller: c, orderId: 'T1'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // Header badge: mode + paid state (ui-checklist: payment method used).
      expect(find.textContaining('UPI'), findsWidgets);
      expect(find.textContaining('Paid'), findsWidgets);
      // Vendor-collect note renders because paymentsPaise > 0.
      expect(find.textContaining('Vendor ko'), findsOneWidget);
      // Bill row is tappable (InkWell, was dead Container).
      await tester.tap(find.textContaining('Bill dekhein'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Bill screen shows the Mode line with the same badge.
      expect(find.text('Mode'), findsOneWidget);
      expect(find.textContaining('UPI'), findsWidgets);
      c.stopTracking();
      c.dispose();
    });
  });
}
