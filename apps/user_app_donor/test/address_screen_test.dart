import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shodasha_donor/core/api_client.dart';
import 'package:shodasha_donor/features/addresses/address_screen.dart';
import 'package:shodasha_donor/features/addresses/map_picker.dart';
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
          'label': 'Office',
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
    expect(find.text('Office'), findsOneWidget);

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

  testWidgets('map picker displays human-readable pin prompt when no pin is placed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => pickMapPin(context),
            child: const Text('Open Picker'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Picker'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Tap the map to place your delivery pin'), findsOneWidget);
  });

  testWidgets('map picker displays human-readable pin feedback when pin is set', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => pickMapPin(
              context,
              initial: const LatLng(23.2599, 77.4126),
            ),
            child: const Text('Open Picker With Pin'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Picker With Pin'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Pin placed · Tap map to adjust location'), findsOneWidget);
  });
}
