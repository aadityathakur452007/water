// 011-grocery-verify — runtime proof the grocery lift is actually rendered
// (shapes + motion, not just source): greeting header, pill search, section
// header, slim 2-col grid with corner add buttons, staggered Animate
// wrappers, and the tap-card → buy-box path with its lifted shape.
// MockClient-free: home + buy-box touch no API. No backend.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_app/core/theme.dart';
import 'package:shodasha_app/features/booking/booking_controller.dart';
import 'package:shodasha_app/features/booking/home_screen.dart';

Future<void> _pumpHome(WidgetTester tester, BookingController c) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildShodashaTheme(),
      home: HomeScreen(controller: c),
    ),
  );
  await tester.pump();
  // Flush the card-stagger clock (same pattern as wave1_ux_test).
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

void main() {
  testWidgets('home renders the lifted grocery shapes', (tester) async {
    final c = BookingController();
    await _pumpHome(tester, c);

    // Greeting header rhythm (overline slot + bold title).
    expect(find.text('Paani book karein'), findsOneWidget);
    // Pill search.
    expect(find.text('Khoj'), findsOneWidget);
    // Section-header row (filter-aware title).
    expect(find.text('Sab products'), findsOneWidget);
    // Slim 2-col grid: photo cards with name + price + corner add.
    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Refill (20L)'), findsOneWidget);
    expect(find.text('Jar + Container (20L)'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNWidgets(2));
    // Staggered entrances are wired (Animate wrappers present).
    expect(find.byType(Animate), findsWidgets);
    c.dispose();
  });

  testWidgets('tap card opens the lifted buy-box', (tester) async {
    final c = BookingController();
    await _pumpHome(tester, c);

    await tester.tap(find.text('Refill (20L)'));
    await tester.pumpAndSettle();

    // Buy-box shape: stepper row, BUY primary, honest deposit facts.
    expect(find.text('Kitne jar?'), findsOneWidget);
    expect(find.textContaining('BUY'), findsOneWidget);
    expect(find.textContaining('refundable deposit'), findsWidgets);
    c.dispose();
  });
}
