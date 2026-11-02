import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/core/api_client.dart';
import 'package:shodasha_donor/features/addresses/address_screen.dart';
import 'package:shodasha_donor/shared/ui/app_button.dart';

class _EmptyAddressApi extends ApiClient {
  _EmptyAddressApi() : super(accessToken: 'test-token');

  @override
  Future<List<dynamic>> listAddresses() async => [];
}

class _PopulatedAddressApi extends ApiClient {
  _PopulatedAddressApi() : super(accessToken: 'test-token');

  @override
  Future<List<dynamic>> listAddresses() async => [
        {
          'id': 'addr-1',
          'label': 'Home',
          'type': 'home',
          'phone': '9876543210',
          'pincode': '462001',
          'formatted': '123, Main Road, Bhopal',
          'landmark': 'Near Park',
          'has_lift': true,
          'is_default': true,
          'lat': 23.2599,
          'lng': 77.4126,
          'house': '123',
          'street': 'Main Road',
          'area': 'MP Nagar',
        },
        {
          'id': 'addr-2',
          'label': 'Work',
          'type': 'office',
          'phone': '9876543211',
          'pincode': '462016',
          'formatted': '456, Kolar Road, Bhopal',
          'landmark': 'Opp Bank',
          'has_lift': false,
          'is_default': false,
          'lat': 23.2324,
          'lng': 77.4295,
          'house': '456',
          'street': 'Kolar Road',
          'area': 'Chuna Bhatti',
        },
      ];
}

class _ThreeAddressApi extends ApiClient {
  _ThreeAddressApi() : super(accessToken: 'test-token');

  @override
  Future<List<dynamic>> listAddresses() async => [
        {
          'id': 'addr-1',
          'label': 'Home',
          'type': 'home',
          'phone': '9876543210',
          'pincode': '462001',
          'formatted': '123, Main Road, Bhopal',
          'landmark': 'Near Park',
          'has_lift': true,
          'is_default': true,
          'lat': 23.2599,
          'lng': 77.4126,
          'house': '123',
          'street': 'Main Road',
          'area': 'MP Nagar',
        },
        {
          'id': 'addr-2',
          'label': 'Work',
          'type': 'office',
          'phone': '9876543211',
          'pincode': '462016',
          'formatted': '456, Kolar Road, Bhopal',
          'landmark': 'Opp Bank',
          'has_lift': false,
          'is_default': false,
          'lat': 23.2324,
          'lng': 77.4295,
          'house': '456',
          'street': 'Kolar Road',
          'area': 'Chuna Bhatti',
        },
        {
          'id': 'addr-3',
          'label': 'Other (Gym)',
          'type': 'other',
          'phone': '9876543212',
          'pincode': '462022',
          'formatted': '789, Shahpura, Bhopal',
          'landmark': 'Near Lake',
          'has_lift': true,
          'is_default': false,
          'lat': 23.2100,
          'lng': 77.4300,
          'house': '789',
          'street': 'Shahpura',
          'area': 'Sector B',
        },
      ];
}

void main() {
  testWidgets('empty state renders AppButton with primary styling for add first', (tester) async {
    final controller = AddressController(api: _EmptyAddressApi());
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: AddressScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(addressStrings['emptyTitle']!), findsOneWidget);
    final buttonFinder = find.widgetWithText(AppButton, addressStrings['addFirst']!);
    expect(buttonFinder, findsOneWidget);
    final appButton = tester.widget<AppButton>(buttonFinder);
    expect(appButton.kind, AppButtonKind.primary);
  });

  testWidgets('populated state renders sticky bottom AppButton and list items without tail button', (tester) async {
    final controller = AddressController(api: _PopulatedAddressApi());
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: AddressScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    // Verify address cards are present
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('2 of 3 saved'), findsOneWidget);

    // Verify sticky bottom AppButton is rendered
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.bottomNavigationBar, isNotNull);

    final stickyButtonFinder = find.descendant(
      of: find.byType(SafeArea),
      matching: find.widgetWithText(AppButton, addressStrings['addFirst']!),
    );
    expect(stickyButtonFinder, findsOneWidget);

    // Verify no ElevatedButton is rendered as a list-tail button
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('tapping add address opens tag-first sheet with Home, Work, Other tags and no map', (tester) async {
    final controller = AddressController(api: _PopulatedAddressApi());
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: AddressScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    // Tap sticky add button
    final stickyButton = find.descendant(
      of: find.byType(SafeArea),
      matching: find.widgetWithText(AppButton, addressStrings['addFirst']!),
    );
    await tester.tap(stickyButton);
    await tester.pumpAndSettle();

    // Verify modal bottom sheet is open
    expect(find.byType(BottomSheet), findsOneWidget);

    // Verify sheet title within BottomSheet
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(addressStrings['addTitle']!),
      ),
      findsOneWidget,
    );

    // Verify tag chips within BottomSheet
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Home'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Work'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Other'),
      ),
      findsOneWidget,
    );

    // Verify manual Indian address fields
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text(addressStrings['house']!)), findsOneWidget);
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text(addressStrings['addressLine']!)), findsOneWidget);
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text(addressStrings['pincode']!)), findsOneWidget);
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text(addressStrings['landmark']!)), findsOneWidget);
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text(addressStrings['lift']!)), findsOneWidget);

    // Verify lift water logistics helper copy is present
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text(addressStrings['liftHelper']!)), findsOneWidget);
  });

  testWidgets('reaches 3-address limit: locks add button and informs user', (tester) async {
    final controller = AddressController(api: _ThreeAddressApi());
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: AddressScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3 of 3 saved'), findsOneWidget);

    // Verify locked bottom CTA
    final lockedButtonText = 'All 3 address slots used (Home, Work, Other)';
    expect(find.text(lockedButtonText), findsOneWidget);

    // Tap the locked button and verify informative SnackBar
    await tester.tap(find.text(lockedButtonText));
    await tester.pumpAndSettle();

    expect(find.text(addressStrings['maxReached']!), findsOneWidget);
  });
}
