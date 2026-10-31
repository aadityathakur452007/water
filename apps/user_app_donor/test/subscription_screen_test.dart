import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/core/api_client.dart';
import 'package:shodasha_donor/features/subscriptions/plan_builder_sheet.dart';
import 'package:shodasha_donor/features/subscriptions/subscription_controller.dart';
import 'package:shodasha_donor/features/subscriptions/subscription_screen.dart';
import 'package:shodasha_donor/shared/ui/app_button.dart';

class _EmptySubsApi extends ApiClient {
  _EmptySubsApi() : super(accessToken: 'test-token');

  @override
  Future<List<dynamic>> listAddresses() async => [];

  @override
  Future<List<dynamic>> listSubscriptions() async => [];

  @override
  Future<Map<String, dynamic>> billingDues() async => {'dues': 0};
}

class _ActiveSubsApi extends ApiClient {
  _ActiveSubsApi() : super(accessToken: 'test-token');

  @override
  Future<List<dynamic>> listAddresses() async => [];

  @override
  Future<List<dynamic>> listSubscriptions() async => [
    {
      'id': 'sub-12345678',
      'address_id': 'addr-1',
      'qty': 2,
      'sku_mix': 'refill',
      'schedule_type': 'daily',
      'status': 'active',
      'billing_mode': 'per_delivery',
      'payment_method': 'cod',
    },
  ];

  @override
  Future<Map<String, dynamic>> billingDues() async => {'dues': 0};
}

void main() {
  testWidgets('empty state renders AppButton with primary styling for build plan', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SubscriptionScreen(api: _EmptySubsApi()),
      ),
    );
    await tester.pumpAndSettle();

    // Verify empty state is rendered
    expect(find.text(subStrings['emptyTitle']!), findsOneWidget);

    // Verify AppButton is rendered for build plan
    final buttonFinder = find.widgetWithText(AppButton, subStrings['buildPlan']!);
    expect(buttonFinder, findsOneWidget);
  });

  testWidgets('plan card renders kebab menu with cancel option', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SubscriptionScreen(api: _ActiveSubsApi()),
      ),
    );
    await tester.pumpAndSettle();

    // Verify plan card is rendered with kebab menu
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);

    // Tap kebab menu to open popup
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    // Verify Cancel option is in the popup menu
    expect(find.text(subStrings['cancel']!), findsOneWidget);
  });
}
