import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rider_app/core/api_client.dart';
import 'package:rider_app/features/delivery/widgets/pod_sheet.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super();
}

void main() {
  group('HandoverMode State Machine Resolution', () {
    test('daily subscription resolves to HandoverMode.dailySubscription', () {
      final stop = {
        'is_subscription': true,
        'is_monthly_dues': false,
        'amount_due': 0,
        'payment_mode': 'cod',
      };
      expect(resolveHandoverMode(stop), equals(HandoverMode.dailySubscription));
    });

    test('month-end dues with amount_due > 0 resolves to HandoverMode.monthEndDues', () {
      final stop = {
        'is_subscription': true,
        'is_monthly_dues': true,
        'amount_due': 5600,
        'payment_mode': 'cod',
      };
      expect(resolveHandoverMode(stop), equals(HandoverMode.monthEndDues));
    });

    test('standard COD with amount_due > 0 resolves to HandoverMode.standardCod', () {
      final stop = {
        'is_subscription': false,
        'is_monthly_dues': false,
        'amount_due': 2800,
        'payment_mode': 'cod',
      };
      expect(resolveHandoverMode(stop), equals(HandoverMode.standardCod));
    });

    test('prepaid UPI resolves to HandoverMode.prepaid', () {
      final stop = {
        'is_subscription': false,
        'is_monthly_dues': false,
        'payment_status': 'paid_upi',
        'amount_due': 0,
        'payment_mode': 'upi',
      };
      expect(resolveHandoverMode(stop), equals(HandoverMode.prepaid));
    });
  });

  group('PodSheet UI Mode Rendering', () {
    testWidgets('daily subscription renders monthly banner and hides cash collection checkbox', (tester) async {
      final stop = {
        'id': 'stop-sub-1',
        'customer_name': 'Aaditya',
        'customer_phone': '+919713710316',
        'quantity': 1,
        'empties_expected': 1,
        'is_subscription': true,
        'is_monthly_dues': false,
        'amount_due': 0,
        'payment_mode': 'cod',
        'address': {'formatted': 'E-8 Arera Colony', 'has_lift': true},
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PodSheet(
              stop: stop,
              api: _FakeApiClient(),
              onSuccess: () {},
            ),
          ),
        ),
      );

      // Verify monthly plan banner is displayed
      expect(find.text('MONTHLY PLAN (मंथली ग्राहक)'), findsOneWidget);
      expect(find.text('Do NOT collect daily cash — ₹0 due today'), findsOneWidget);

      // Verify cash collection checkbox is NOT present
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('month-end dues renders monthly bill cash checkbox', (tester) async {
      final stop = {
        'id': 'stop-dues-1',
        'customer_name': 'Aaditya',
        'customer_phone': '+919713710316',
        'quantity': 1,
        'empties_expected': 1,
        'is_subscription': true,
        'is_monthly_dues': true,
        'amount_due': 8400,
        'payment_mode': 'cod',
        'address': {'formatted': 'E-8 Arera Colony', 'has_lift': true},
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PodSheet(
              stop: stop,
              api: _FakeApiClient(),
              onSuccess: () {},
            ),
          ),
        ),
      );

      // Verify monthly bill text and checkbox are present
      expect(find.text('Collect ₹84 Monthly Bill (महीने का बिल)'), findsOneWidget);
      expect(find.byType(Checkbox), findsOneWidget);
    });
  });
}
