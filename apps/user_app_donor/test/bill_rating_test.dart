import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/core/theme.dart';
import 'package:shodasha_donor/features/orders/bill_screen.dart';
import 'package:shodasha_donor/features/orders/orders_controller.dart';
import 'package:shodasha_donor/features/orders/rating_sheet.dart';
import 'package:shodasha_donor/shared/ui/app_button.dart';

void main() {
  group('BillScreen', () {
    testWidgets('renders truncated 8-char uppercase order ref and enriched SKU line', (
      tester,
    ) async {
      final order = Order(
        id: 'b489021150c8425abd9a23f1af39839e',
        state: OrderState.delivered,
        windowStart: DateTime(2026, 10, 31, 9),
        windowEnd: DateTime(2026, 10, 31, 9, 30),
        itemSummary: '2 × 20L Refill',
        totalPaise: 5600,
        waterBillPaise: 5600,
        depositDuePaise: 0,
        paymentStatus: 'paid_upi',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: BillScreen(order: order),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bill · #B4890211'), findsOneWidget);
      expect(find.text('2 × 20L Refill'), findsOneWidget);
      expect(find.text('Water'), findsNothing);
      expect(find.text('Bill frozen at delivery'), findsOneWidget);

      final helpBtn = tester.widget<AppButton>(find.byType(AppButton));
      expect(helpBtn.label, 'Help on WhatsApp');
      expect(helpBtn.icon, Icons.chat_outlined);
    });
  });

  group('RatingSheet', () {
    testWidgets(
      'hides complaint shortcut on 4-5 stars and reveals on 1-3 stars',
      (tester) async {
        var supportCalled = false;
        final order = Order(
          id: 'ord-rate-1',
          state: OrderState.delivered,
          windowStart: DateTime(2026, 10, 31, 9),
        );
        final repo = StubOrdersRepository([order]);
        final controller = OrdersController(repo: repo);

        await tester.pumpWidget(
          MaterialApp(
            theme: buildShodashaTheme(),
            home: Scaffold(
              body: RatingSheet(
                controller: controller,
                order: order,
                onSupport: () => supportCalled = true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 0 stars: submit button disabled, complaint shortcut hidden
        final submitFinder = find.widgetWithText(AppButton, 'Submit rating');
        expect(submitFinder, findsOneWidget);
        expect(tester.widget<AppButton>(submitFinder).onPressed, isNull);
        expect(find.text('Something wrong? File a complaint'), findsNothing);

        // Tap 5 stars: submit enabled, complaint shortcut remains hidden
        await tester.tap(find.byTooltip('5 / 5'));
        await tester.pumpAndSettle();
        expect(tester.widget<AppButton>(submitFinder).onPressed, isNotNull);
        expect(find.text('Something wrong? File a complaint'), findsNothing);

        // Tap 2 stars: submit enabled, complaint shortcut REVEALED
        await tester.tap(find.byTooltip('2 / 5'));
        await tester.pumpAndSettle();
        expect(find.text('Something wrong? File a complaint'), findsOneWidget);

        // Tap complaint shortcut
        await tester.tap(find.text('Something wrong? File a complaint'));
        await tester.pumpAndSettle();
        expect(supportCalled, isTrue);
      },
    );
  });
}
