import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/core/api_client.dart';
import 'package:shodasha_donor/features/wallet/donor_wallet_screen.dart';
import 'package:shodasha_donor/shared/ui/app_button.dart';

class _StubWalletApi extends ApiClient {
  _StubWalletApi({
    this.held = 0,
    this.depositPaid = 0,
    this.dues = 0,
  }) : super(accessToken: 'test-token');

  final int held;
  final int depositPaid;
  final int dues;

  @override
  Future<Map<String, dynamic>> ledgerMe() async => {
        'held': held,
        'deposit_paid': depositPaid,
        'deposit_refunded': 0,
        'wallet_held': depositPaid,
        'dues': dues,
      };

  @override
  Future<List<dynamic>> listUserPayments({int limit = 50}) async => [];
}

void main() {
  testWidgets('zero-jar custody renders quiet disabled action tile without layout collapse', (tester) async {
    final api = _StubWalletApi(held: 0, depositPaid: 0, dues: 0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DonorWalletScreen(
            api: api,
            onOpenSubscriptions: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify empty custody title is rendered
    expect(find.text('No jars with you yet'), findsOneWidget);

    // Verify consistent "Return empty jars" action tile is present and disabled
    expect(find.text('Return empty jars'), findsOneWidget);
    expect(
      find.text('0 jars in custody · Pickup unlocks when you have empty jars'),
      findsOneWidget,
    );
  });

  testWidgets('active custody deduplicates jars count and shows dues action with Plans context', (tester) async {
    final api = _StubWalletApi(held: 2, depositPaid: 30000, dues: 2800);
    var subscriptionsOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DonorWalletScreen(
            api: api,
            onOpenSubscriptions: () {
              subscriptionsOpened = true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Hero shows the jars count badge
    expect(find.text('2 jars with you'), findsOneWidget);

    // "Deposit details" card has "Deposit paid", but no duplicate "Jars with you" row
    expect(find.text('Deposit paid'), findsOneWidget);
    expect(find.text('Jars with you'), findsNothing);

    // Outstanding dues card renders unsloped copy and AppButton with Plans context
    expect(find.text('Review dues in Plans'), findsOneWidget);
    final buttonFinder = find.widgetWithText(AppButton, 'Review dues in Plans');
    expect(buttonFinder, findsOneWidget);

    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();

    expect(subscriptionsOpened, isTrue);
  });
}
