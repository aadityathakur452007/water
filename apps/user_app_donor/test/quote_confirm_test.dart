import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/core/theme.dart';
import 'package:shodasha_donor/features/booking/checkout_service.dart';
import 'package:shodasha_donor/features/booking/quote_confirm.dart';
import 'package:shodasha_donor/features/booking/stepper.dart';

void main() {
  testWidgets('quote confirm sheet renders order confirmed status', (
    tester,
  ) async {
    const result = CheckoutResult(
      orderId: 'ord-test-1234',
      totalPaise: 2800,
      windowLabel: 'Tomorrow 8:00 AM – 8:30 AM',
      isSubscription: false,
      addressLabel: 'Home · Arera Colony',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showOrderConfirm(ctx, result: result),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Order confirmed'), findsOneWidget);
    expect(find.text('Order: ord-test-1234'), findsOneWidget);
    expect(find.text('Window: Tomorrow 8:00 AM – 8:30 AM'), findsOneWidget);
  });

  testWidgets(
    'quote confirm sheet renders sanitized awaiting payment copy when attention is set',
    (tester) async {
      const result = CheckoutResult(
        orderId: 'ord-test-5678',
        totalPaise: 5600,
        windowLabel: 'Tomorrow 9:00 AM – 9:30 AM',
        isSubscription: false,
        attention: true,
        attentionMessage: 'Payment pending — complete in UPI app or pay cash.',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showOrderConfirm(ctx, result: result),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Order placed · Awaiting payment'), findsOneWidget);
      expect(
        find.text('Payment pending — complete in UPI app or pay cash.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('QtyStepper steps and respects bounds', (tester) async {
    int current = 2;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => QtyStepper(
              value: current,
              min: 1,
              max: 5,
              onChanged: (val) => setState(() => current = val),
            ),
          ),
        ),
      ),
    );

    expect(find.text('2'), findsOneWidget);

    // Increase
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(current, 3);
    expect(find.text('3'), findsOneWidget);

    // Decrease
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(current, 2);
    expect(find.text('2'), findsOneWidget);
  });
}
