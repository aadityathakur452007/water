import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/core/api_client.dart';
import 'package:rider_app/features/auth/login_screen.dart';
import 'package:rider_app/features/delivery/delivery_screen.dart';
import 'package:rider_app/features/delivery/widgets/pod_sheet.dart';
import 'package:rider_app/main.dart';
import 'package:rider_app/shared/ui/app_button.dart';

class _MockRiderApi extends ApiClient {
  _MockRiderApi({this.authed = false});

  final bool authed;

  @override
  bool get isAuthenticated => authed;

  @override
  Map<String, dynamic>? get riderUser => authed
      ? {'id': 'r1', 'name': 'Ramesh Rider', 'phone': '+919876500003'}
      : null;

  @override
  Future<Map<String, dynamic>> getTodayRoute() async => {
        'route_id': 'route-1',
        'date': '2026-11-02',
        'stops': [
          {
            'id': 'stop-1',
            'seq': 1,
            'status': 'pending',
            'order_id': 'o1',
            'customer_name': 'Ram Sharma',
            'customer_phone': '9876543210',
            'quantity': 2,
            'empties_expected': 2,
            'payment_mode': 'cod',
            'is_paid': false,
            'amount_due': 14000,
            'address': {
              'formatted': 'Flat 402, Royal Palms, MP Nagar',
              'landmark': 'Near Bank',
              'has_lift': true,
            },
            'instructions': 'Please ring bell twice',
          },
        ],
        'summary': {
          'total': 1,
          'delivered': 0,
          'pending': 1,
        },
      };

  @override
  Future<Map<String, dynamic>> completeDelivery({
    required String stopId,
    required String deliveryOtp,
    int emptiesCount = 0,
    int cash = 0,
  }) async {
    return {'status': 'delivered', 'stop_id': stopId};
  }
}

void main() {
  testWidgets('unauthenticated boot mounts LoginScreen with rider branding', (tester) async {
    final api = _MockRiderApi(authed: false);

    await tester.pumpWidget(RiderApp(api: api));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Shodasha Rider'), findsOneWidget);
    expect(find.text('Start Delivery Shift'), findsOneWidget);
    expect(find.text('Your Name'), findsOneWidget);
    expect(find.text('Mobile Number'), findsOneWidget);
  });

  testWidgets('authenticated boot mounts DeliveryScreen with today stops and lift badge', (tester) async {
    final api = _MockRiderApi(authed: true);

    await tester.pumpWidget(RiderApp(api: api));
    await tester.pumpAndSettle();

    expect(find.byType(DeliveryScreen), findsOneWidget);
    expect(find.text('Ramesh Rider'), findsOneWidget);
    expect(find.text('Ram Sharma'), findsOneWidget);
    expect(find.text('Flat 402, Royal Palms, MP Nagar'), findsOneWidget);
    expect(find.text('2 × 20L Cane'), findsOneWidget);
    expect(find.text('Lift Available'), findsOneWidget);
    expect(find.text('Collect ₹140 Cash'), findsOneWidget);

    // Verify Mark Delivered button is rendered
    expect(find.widgetWithText(AppButton, 'Mark Delivered (Enter OTP)'), findsOneWidget);
  });

  testWidgets('tapping Mark Delivered opens PodSheet with OTP input and empties counter', (tester) async {
    final api = _MockRiderApi(authed: true);

    await tester.pumpWidget(RiderApp(api: api));
    await tester.pumpAndSettle();

    // Tap mark delivered button
    await tester.tap(find.widgetWithText(AppButton, 'Mark Delivered (Enter OTP)'));
    await tester.pumpAndSettle();

    expect(find.byType(PodSheet), findsOneWidget);
    expect(find.text('DOORSTEP HANDOVER'), findsOneWidget);
    expect(find.text('Customer Delivery OTP'), findsOneWidget);
    expect(find.text('Empty Canes Collected'), findsOneWidget);
    expect(find.descendant(of: find.byType(PodSheet), matching: find.text('Collect ₹140 Cash')), findsOneWidget);
    expect(find.text('Verify OTP & Mark Delivered'), findsOneWidget);
  });
}
