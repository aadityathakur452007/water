import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/core/api_client.dart';
import 'package:shodasha_donor/features/subscriptions/plan_builder_sheet.dart';
import 'package:shodasha_donor/features/subscriptions/subscription_controller.dart';
import 'package:shodasha_donor/features/subscriptions/subscription_screen.dart';

/// Regression coverage for the monthly-money contract in the donor UI:
/// billing/payment are explicit, monthly forces UPI, prepaid stays pending
/// until the server confirms, and cancel copy never invents a refund.
void main() {
  group('subscription billing payload', () {
    test('parses server billing fields and never calls pending active', () {
      final pending = SubscriptionEntry.fromApi({
        'id': 's1',
        'billing_mode': 'monthly_prepaid',
        'payment_method': 'upi',
        'billing_status': 'pending_payment',
        'credit_balance_paise': 0,
        'low_balance': true,
      });
      expect(pending.isPrepaid, isTrue);
      expect(pending.awaitingPayment, isTrue);
      expect(pending.lowBalance, isTrue);

      final canceled = SubscriptionEntry.fromApi({
        'id': 's2',
        'billing_mode': 'monthly_prepaid',
        'billing_status': 'pending_payment',
        'canceled_at': '2026-10-24T00:00:00+00:00',
      });
      expect(canceled.canceled, isTrue);
      expect(canceled.awaitingPayment, isFalse);

      final perDelivery = SubscriptionEntry.fromApi({'id': 's3'});
      expect(perDelivery.billingMode, 'per_delivery');
      expect(perDelivery.paymentMethod, 'cod');
      expect(perDelivery.awaitingPayment, isFalse);
    });

    test('honest cancel copy has no unearned refund promise', () {
      expect(subStrings['cancelBody'], contains('paid for deliveries'));
      expect(subStrings['cancelDoneBody'], isNot(contains('on its way')));
      expect(subStrings['cancelNoRefund'], contains('No refund is due'));
    });

    testWidgets('monthly prepaid sends UPI and shows the server top-up', (
      tester,
    ) async {
      final api = _BuilderApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showPlanBuilderSheet(ctx, api: api),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Monthly prepaid'));
      await tester.tap(find.text('Monthly prepaid'));
      await tester.pumpAndSettle();

      // Monthly plans are UPI-only, and the estimate is the server's top-up.
      expect(find.textContaining('covers 30 days of water'), findsOneWidget);
      await tester.ensureVisible(find.text('Cash on delivery'));
      await tester.tap(find.text('Cash on delivery'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text(subStrings['startPlan']!));
      await tester.tap(find.text(subStrings['startPlan']!));
      await tester.pumpAndSettle();

      expect(api.createCalls, 1);
      expect(api.billingMode, 'monthly_prepaid');
      expect(api.paymentMethod, 'upi');
      expect(api.idempotencyKey, isNotEmpty);
    });

    testWidgets('prepaid card shows awaiting payment, balance and top-up', (
      tester,
    ) async {
      final api = _ScreenApi();
      await tester.pumpWidget(MaterialApp(home: SubscriptionScreen(api: api)));
      await tester.pumpAndSettle();

      expect(find.text('Awaiting payment'), findsOneWidget);
      expect(find.text(subStrings['prepaidBalance']!), findsOneWidget);
      expect(find.text(subStrings['addTopUp']!), findsOneWidget);
      expect(find.text(subStrings['lowBalance']!), findsOneWidget);
      expect(find.text(subStrings['billingPrepaid']!), findsOneWidget);
      expect(find.text(subStrings['paymentUpi']!), findsOneWidget);
    });
  });
}

class _BuilderApi extends ApiClient {
  _BuilderApi() : super(accessToken: 'test-token');

  int createCalls = 0;
  String? billingMode;
  String? paymentMethod;
  String? idempotencyKey;

  @override
  Future<List<dynamic>> listAddresses() async => [
    {'id': 'a1', 'label': 'Home'},
  ];

  @override
  Future<Map<String, dynamic>> subscriptionEstimate({
    required int qty,
    required String skuMix,
  }) async => {
    'water_bill': 2800,
    'deposit_due': 15000,
    'total': 17800,
    'monthly_topup_paise': 84000,
    'rate_version': 'v1',
  };

  @override
  Future<Map<String, dynamic>> createSubscription({
    required String addressId,
    required int qty,
    required String skuMix,
    required String window,
    required String scheduleType,
    String recurrence = '',
    String billingMode = 'per_delivery',
    String paymentMethod = 'cod',
    String? idempotencyKey,
  }) async {
    createCalls += 1;
    this.billingMode = billingMode;
    this.paymentMethod = paymentMethod;
    this.idempotencyKey = idempotencyKey;
    return {
      'id': 's1',
      'billing_mode': billingMode,
      'billing_status': billingMode == 'monthly_prepaid'
          ? 'pending_payment'
          : 'active',
    };
  }
}

class _ScreenApi extends ApiClient {
  _ScreenApi() : super(accessToken: 'test-token');

  @override
  Future<List<dynamic>> listAddresses() async => [];

  @override
  Future<List<dynamic>> listSubscriptions() async => [
    {
      'id': 's1',
      'address_id': 'a1',
      'qty': 1,
      'sku_mix': 'refill',
      'billing_mode': 'monthly_prepaid',
      'payment_method': 'upi',
      'billing_status': 'pending_payment',
      'credit_balance_paise': 2799,
      'low_balance': true,
      'status': 'active',
    },
  ];

  @override
  Future<Map<String, dynamic>> billingDues() async => {'dues': 0};
}
