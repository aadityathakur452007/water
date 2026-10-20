// Runtime proof the storefront renders the lifted shapes + motion:
// greeting header, schedule cards, wallet strip, 2-column product grid,
// staggered Animate wrappers, and tap-card → buy-box.
// Rates are an explicit server snapshot; Home touches no API in this test.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_app/core/theme.dart';
import 'package:shodasha_app/features/booking/booking_controller.dart';
import 'package:shodasha_app/features/booking/home_screen.dart';

const _rates = CatalogRates(
  refillPaise: 2800,
  containerPaise: 3000,
  depositPaise: 15000,
  capPaise: 300,
);

Future<void> _pumpHome(WidgetTester tester, BookingController c) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildShodashaTheme(),
      home: HomeScreen(controller: c),
    ),
  );
  await tester.pump();
  // Flush the card-stagger clock.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

void main() {
  testWidgets('home renders the lifted storefront shapes', (tester) async {
    final c = BookingController(initialRates: _rates);
    await _pumpHome(tester, c);

    expect(find.text('Book water'), findsOneWidget);
    expect(find.text('Choose your schedule'), findsOneWidget);
    expect(find.text('One-time'), findsOneWidget);
    expect(find.text('Daily plan'), findsOneWidget);
    expect(find.text('ALL PRODUCTS'), findsOneWidget);

    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Refill (20L)'), findsOneWidget);
    expect(find.text('Jar + Container (20L)'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNWidgets(2));
    expect(find.byType(Animate), findsWidgets);
    c.dispose();
  });

  testWidgets('tap card opens the buy-box', (tester) async {
    final c = BookingController(initialRates: _rates);
    await _pumpHome(tester, c);

    final card = find.text('Refill (20L)');
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(find.text('How many jars?'), findsOneWidget);
    expect(find.textContaining('BUY'), findsOneWidget);
    expect(find.textContaining('safety deposit'), findsWidgets);
    c.dispose();
  });

  testWidgets('BOOK NOW is disabled until a jar is chosen', (tester) async {
    final c = BookingController(initialRates: _rates);
    await _pumpHome(tester, c);

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'BOOK NOW • Choose at least 1 jar'),
    );
    expect(button.onPressed, isNull);
    c.dispose();
  });
}
