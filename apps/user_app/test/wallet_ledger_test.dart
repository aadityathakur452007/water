// S7 wallet spec (ported/expanded from legacy payment_history_test.dart).
//
// Covers: ledger parsing (server + legacy shapes), loaded hero, honest empty,
// error + retry, guest with zero network, return payload {qty, address_id,
// upi_id}, and the injected address picker. Plugin-free (mocked http).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/core/theme.dart';
import 'package:shodasha_app/features/returns/return_sheet.dart';
import 'package:shodasha_app/features/returns/returns_controller.dart';
import 'package:shodasha_app/features/wallet/wallet_controller.dart';
import 'package:shodasha_app/features/wallet/wallet_screen.dart';

Map<String, dynamic> _ledger({
  int held = 0,
  int paid = 0,
  int refunded = 0,
  int walletHeld = 0,
  int dues = 0,
}) => {
  'held': held,
  'deposit_paid': paid,
  'deposit_refunded': refunded,
  'wallet_held': walletHeld,
  'dues': dues,
};

Widget _app(Widget home) =>
    MaterialApp(theme: buildShodashaTheme(), home: home);

void main() {
  group('LedgerSnapshot', () {
    test('parses the canonical GET /ledger/me shape (paise, ints)', () {
      final l = LedgerSnapshot.fromApi({
        'held': 2,
        'deposit_paid': 30000,
        'deposit_refunded': 15000,
        'wallet_held': 15000,
        'dues': 5600,
      });
      expect(l.heldJars, 2);
      expect(l.depositPaidPaise, 30000);
      expect(l.depositRefundedPaise, 15000);
      // wallet_held is the server's net figure — never recomputed client-side.
      expect(l.depositHeldPaise, 15000);
      expect(l.duesPaise, 5600);
      expect(l.isEmpty, isFalse);
    });

    test('tolerates legacy aliases and string numbers', () {
      final l = LedgerSnapshot.fromApi({
        'held_jars': '1',
        'd_deposit': '15000',
        'd_dues': '300',
      });
      expect(l.heldJars, 1);
      expect(l.depositHeldPaise, 15000);
      expect(l.duesPaise, 300);
    });

    test('all-zero server snapshot is empty (no fake hero)', () {
      expect(LedgerSnapshot.fromApi(_ledger()).isEmpty, isTrue);
    });
  });

  group('WalletScreen', () {
    testWidgets('loaded ledger shows only server amounts', (tester) async {
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/ledger/me')) {
          return http.Response(
            jsonEncode(
              _ledger(held: 2, paid: 30000, walletHeld: 30000, dues: 5600),
            ),
            200,
          );
        }
        return http.Response('not found', 404);
      });
      final api = ApiClient(
        client: mock,
        deviceId: 'test-device',
        accessToken: 't',
      );

      await tester.pumpWidget(
        _app(WalletScreen(api: api, isAuthenticated: () => true)),
      );
      await tester.pumpAndSettle();

      expect(find.text('REFUNDABLE DEPOSIT'), findsOneWidget);
      expect(find.text('₹300'), findsNWidgets(2)); // hero + deposit paid
      expect(find.text('2 jars with you'), findsOneWidget);
      expect(find.text('Jars with you'), findsOneWidget);
      expect(find.text('Dues'), findsOneWidget);
      expect(find.text('₹56'), findsOneWidget);
      expect(find.text('Payments & deposits'), findsOneWidget);
      expect(find.text('Return jars'), findsOneWidget);
    });

    testWidgets('empty ledger explains itself and never renders a ₹0 hero', (
      tester,
    ) async {
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/ledger/me')) {
          return http.Response(jsonEncode(_ledger()), 200);
        }
        return http.Response('not found', 404);
      });
      final api = ApiClient(
        client: mock,
        deviceId: 'test-device',
        accessToken: 't',
      );

      await tester.pumpWidget(
        _app(WalletScreen(api: api, isAuthenticated: () => true)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nothing on your jar account yet'), findsOneWidget);
      expect(find.text('₹0'), findsNothing);
      expect(find.text('REFUNDABLE DEPOSIT'), findsNothing);
    });

    testWidgets('error shows retry and recovers on tap', (tester) async {
      var ledgerCalls = 0;
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/ledger/me')) {
          ledgerCalls += 1;
          if (ledgerCalls == 1) {
            return http.Response(
              jsonEncode({
                'error': {
                  'code': 'VALIDATION',
                  'message': 'Bad request',
                  'details': {},
                },
              }),
              400,
            );
          }
          return http.Response(
            jsonEncode(_ledger(held: 1, paid: 15000, walletHeld: 15000)),
            200,
          );
        }
        return http.Response('not found', 404);
      });
      final api = ApiClient(
        client: mock,
        deviceId: 'test-device',
        accessToken: 't',
      );

      await tester.pumpWidget(
        _app(WalletScreen(api: api, isAuthenticated: () => true)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load your ledger'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('₹0'), findsNothing);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(ledgerCalls, 2);
      expect(find.text('REFUNDABLE DEPOSIT'), findsOneWidget);
      expect(find.text('₹150'), findsNWidgets(2)); // hero + deposit paid
    });

    testWidgets('guest sees login state without firing any request', (
      tester,
    ) async {
      var hits = 0;
      final mock = MockClient((req) async {
        hits += 1;
        return http.Response(jsonEncode(_ledger()), 200);
      });
      final api = ApiClient(client: mock, deviceId: 'test-device');

      await tester.pumpWidget(
        _app(
          WalletScreen(
            api: api,
            isAuthenticated: () => false,
            onLoginRequired: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(hits, 0);
      expect(find.text('Log in to see your jar ledger'), findsOneWidget);
      expect(find.text('Log in'), findsOneWidget);
    });
  });

  group('Returns', () {
    test('controller posts exactly {qty, address_id, upi_id}', () async {
      http.Request? captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({
            'id': 'ret_1',
            'qty': 2,
            'status': 'requested',
            'sla_due': '2026-11-03',
            'refund_paise': 30000,
          }),
          201,
        );
      });
      final api = ApiClient(
        client: mock,
        deviceId: 'test-device',
        accessToken: 't',
      );
      final controller = ReturnsController(api: api);

      final ok = await controller.submit(
        qty: 2,
        addressId: 'addr_1',
        upiId: 'name@bank',
      );

      expect(ok, isTrue);
      expect(captured!.method, 'POST');
      expect(captured!.url.path, '/v1/returns');
      expect(jsonDecode(captured!.body), {
        'qty': 2,
        'address_id': 'addr_1',
        'upi_id': 'name@bank',
      });
      expect(controller.lastRequest!.id, 'ret_1');
      expect(controller.lastRequest!.slaDue, '2026-11-03');
      // Refund comes from the response only — no client multiplication.
      expect(controller.lastRequest!.refundPaise, 30000);
    });

    test('controller validates before the socket', () async {
      var hits = 0;
      final mock = MockClient((req) async {
        hits += 1;
        return http.Response('{}', 201);
      });
      final controller = ReturnsController(
        api: ApiClient(client: mock, deviceId: 'test-device', accessToken: 't'),
      );

      final ok = await controller.submit(qty: 1, addressId: '  ');

      expect(ok, isFalse);
      expect(hits, 0);
      expect(controller.error, isNotNull);
    });

    testWidgets('sheet picks the injected address and files the request', (
      tester,
    ) async {
      Map<String, dynamic>? returnBody;
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/ledger/me')) {
          return http.Response(
            jsonEncode(_ledger(held: 2, paid: 30000, walletHeld: 30000)),
            200,
          );
        }
        if (req.url.path.endsWith('/returns') && req.method == 'POST') {
          returnBody = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'id': 'ret_1',
              'qty': 2,
              'status': 'requested',
              'sla_due': '2026-11-03',
              'message':
                  'Return requested. Pickup within 10 working days (by 2026-11-03).',
            }),
            201,
          );
        }
        return http.Response('not found', 404);
      });
      final api = ApiClient(
        client: mock,
        deviceId: 'test-device',
        accessToken: 't',
      );

      await tester.pumpWidget(
        _app(
          WalletScreen(
            api: api,
            isAuthenticated: () => true,
            pickAddress: (_) async =>
                const ReturnAddress(id: 'addr_1', label: 'Home'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Request return'));
      await tester.pumpAndSettle();

      expect(find.text('Pickup + refund in 10 working days.'), findsOneWidget);
      expect(find.text('Choose pickup address'), findsOneWidget);

      await tester.tap(find.text('Choose pickup address'));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);

      await tester.tap(find.byTooltip('Add one jar'));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'name@bank');
      await tester.pump();

      await tester.ensureVisible(find.text('Send request'));
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(returnBody, {
        'qty': 2,
        'address_id': 'addr_1',
        'upi_id': 'name@bank',
      });
      expect(
        find.textContaining('Return requested. Pickup within 10 working days'),
        findsOneWidget,
      );
      // Let the success snackbar dismiss so no timer outlives the test.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('sheet without an address picker stays honest and disabled', (
      tester,
    ) async {
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/ledger/me')) {
          return http.Response(
            jsonEncode(_ledger(held: 1, paid: 15000, walletHeld: 15000)),
            200,
          );
        }
        return http.Response('not found', 404);
      });
      final api = ApiClient(
        client: mock,
        deviceId: 'test-device',
        accessToken: 't',
      );

      await tester.pumpWidget(
        _app(WalletScreen(api: api, isAuthenticated: () => true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request return'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Address selection is unavailable'),
        findsOneWidget,
      );
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
    });
  });
}
