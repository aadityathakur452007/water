import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shodasha_donor/features/addresses/first_run_sheet.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('scrim/barrier dismiss leaves first-run flag unset', (
    tester,
  ) async {
    var addCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => maybeOfferFirstRun(
                context,
                onAddAddress: () => addCalled = true,
              ),
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );

    // Open sheet
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Where should we deliver?'), findsOneWidget);
    expect(
      find.text(
        'Save your address once for 1-tap reordering. You can edit it anytime.',
      ),
      findsOneWidget,
    );

    // Tap outside sheet (scrim/barrier)
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('Where should we deliver?'), findsNothing);
    expect(addCalled, isFalse);

    // Flag must remain unset so prompt is offered again on clean install
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kFirstRunFlag), isNull);
  });

  testWidgets('tapping Add address sets flag and calls onAddAddress', (
    tester,
  ) async {
    var addCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => maybeOfferFirstRun(
                context,
                onAddAddress: () => addCalled = true,
              ),
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    final addButton = find.text('Add address');
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(addCalled, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kFirstRunFlag), isTrue);
  });

  testWidgets('tapping Not now sets flag and does not call onAddAddress', (
    tester,
  ) async {
    var addCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => maybeOfferFirstRun(
                context,
                onAddAddress: () => addCalled = true,
              ),
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    final notNow = find.text('Not now');
    await tester.tap(notNow);
    await tester.pumpAndSettle();

    expect(addCalled, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kFirstRunFlag), isTrue);
  });
}

