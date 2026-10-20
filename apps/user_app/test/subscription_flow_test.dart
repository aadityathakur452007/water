// S6 subscriptions flow — server money, status truth, real idempotent dues.
//
// Plugin-free: MockClient intercepts every request, so no secure storage,
// url_launcher, or platform channels are touched. Amounts asserted here come
// from mocked server payloads; the client never computes them.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/core/theme.dart';
import 'package:shodasha_app/features/subscriptions/subscription_controller.dart';
import 'package:shodasha_app/features/subscriptions/subscription_screen.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(
  body == null ? '' : jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

Widget _app(Widget home) =>
    MaterialApp(theme: buildShodashaTheme(), home: home);

Map<String, dynamic> _sub({
  String status = 'active',
  bool canceledAt = false,
  int dueToday = 0,
}) => {
  'id': 's1',
  'address_id': 'a1',
  'qty': 2,
  'sku_mix': 'refill',
  'window': '7-9 AM',
  'status': status,
  if (canceledAt) 'canceled_at': '2026-10-19T10:00:00Z',
  'next_run': '2026-10-21',
  'due_today_paise': dueToday,
  'monthly_estimate_paise': 168000,
};

ApiClient _api(http.Client client) => ApiClient(
  client: client,
  deviceId: 'test-device',
  accessToken: 'test-token',
);

String? _header(http.Request r, String name) {
  for (final e in r.headers.entries) {
    if (e.key.toLowerCase() == name.toLowerCase()) return e.value;
  }
  return null;
}

class _Log {
  final List<http.Request> requests = [];

  List<http.Request> all(String method, String suffix) => requests
      .where((r) => r.method == method && r.url.path.endsWith(suffix))
      .toList();

  http.Request? last(String method, String suffix) {
    final matches = all(method, suffix);
    return matches.isEmpty ? null : matches.last;
  }
}

/// Canonical read endpoints. Tests override the mutating paths first.
Future<http.Response> _standard(
  http.Request req, {
  List<Map<String, dynamic>> subs = const [],
  int dues = 0,
  bool duesFails = false,
}) async {
  final p = req.url.path;
  if (req.method == 'GET' && p.endsWith('/subscriptions')) {
    return _json({'data': subs});
  }
  if (req.method == 'GET' && p.endsWith('/addresses')) {
    return _json([
      {'id': 'a1', 'label': 'Home', 'pincode': '560001'},
    ]);
  }
  if (req.method == 'GET' && p.endsWith('/billing/dues')) {
    return duesFails
        ? _json({
            'error': {'code': 'FORBIDDEN', 'message': 'no dues access'},
          }, 403)
        : _json({'dues': dues});
  }
  return _json({
    'error': {'code': 'NOT_FOUND', 'message': 'unexpected route'},
  }, 404);
}

Future<void> _pumpScreen(
  WidgetTester tester,
  ApiClient api, {
  VoidCallback? onOpenWallet,
}) async {
  tester.view.physicalSize = const Size(1200, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    _app(SubscriptionScreen(api: api, onOpenWallet: onOpenWallet)),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('SubscriptionEntry / SubscriptionEstimate', () {
    test('canceled wins over paused (D1 keeps status=paused)', () {
      final e = SubscriptionEntry.fromApi(
        _sub(status: 'paused', canceledAt: true),
      );
      expect(e.canceled, isTrue);
      expect(e.paused, isFalse);
    });

    test('paused maps to paused only; active maps to neither', () {
      final paused = SubscriptionEntry.fromApi(_sub(status: 'paused'));
      expect(paused.paused, isTrue);
      expect(paused.canceled, isFalse);

      final active = SubscriptionEntry.fromApi(_sub());
      expect(active.paused, isFalse);
      expect(active.canceled, isFalse);
    });

    test('server amounts and address labels pass through untouched', () {
      final e = SubscriptionEntry.fromApi(
        _sub(dueToday: 5600),
        addressLabels: const {'a1': 'Home'},
      );
      expect(e.addressLabel, 'Home');
      expect(e.dueTodayPaise, 5600);
      expect(e.monthlyEstimatePaise, 168000);
    });

    test('missing money stays null — never zero-filled', () {
      final e = SubscriptionEntry.fromApi({
        'id': 's9',
        'qty': 1,
        'status': 'active',
      });
      expect(e.dueTodayPaise, isNull);
      expect(e.monthlyEstimatePaise, isNull);
      expect(e.addressLabel, subStrings['addressFallback']);
    });

    test('estimate parses server paise and rejects a total-less payload', () {
      final est = SubscriptionEstimate.fromApi({
        'total': 5600,
        'water_bill': 5000,
        'deposit_due': 600,
        'rate_version': 'v3',
      });
      expect(est.totalPaise, 5600);
      expect(est.waterBillPaise, 5000);
      expect(est.depositDuePaise, 600);
      expect(est.rateVersion, 'v3');
      expect(
        () => SubscriptionEstimate.fromApi({'water_bill': 5000}),
        throwsFormatException,
      );
    });

    test('rupeesLabel is display formatting only', () {
      expect(rupeesLabel(5600), 'Rs 56');
      expect(rupeesLabel(5650), 'Rs 56.50');
    });
  });

  group('SubscriptionController reads', () {
    test('load maps plans, address labels and server dues', () async {
      final api = _api(
        MockClient(
          (req) => _standard(req, subs: [_sub(dueToday: 1000)], dues: 5600),
        ),
      );
      final c = SubscriptionController(api: api);
      await c.load();
      expect(c.status, SubStatus.loaded);
      expect(c.items, hasLength(1));
      expect(c.items.single.addressLabel, 'Home');
      expect(c.items.single.dueTodayPaise, 1000);
      expect(c.duesPaise, 5600);
      c.dispose();
    });

    test('dues failure is unknown (hidden), never a fake zero', () async {
      final api = _api(
        MockClient((req) => _standard(req, subs: [_sub()], duesFails: true)),
      );
      final c = SubscriptionController(api: api);
      await c.load();
      expect(c.status, SubStatus.loaded);
      expect(c.duesPaise, isNull);
      c.dispose();
    });

    test('401 maps to the signed-out copy and error state', () async {
      final api = _api(
        MockClient(
          (req) async => _json({
            'error': {'code': 'UNAUTH', 'message': 'sign in'},
          }, 401),
        ),
      );
      final c = SubscriptionController(api: api);
      await c.load();
      expect(c.status, SubStatus.error);
      expect(c.errorMessage, subStrings['signedOut']);
      c.dispose();
    });
  });

  group('SubscriptionController mutations', () {
    test('pause validates the range then posts server dates', () async {
      final log = _Log();
      final api = _api(
        MockClient((req) async {
          log.requests.add(req);
          if (req.url.path.endsWith('/pause')) {
            return _json({'id': 's1', 'status': 'paused'}, 201);
          }
          return _standard(req, subs: [_sub(status: 'paused')]);
        }),
      );
      final c = SubscriptionController(api: api);

      expect(await c.pause('s1', '2026-10-20', '2026-10-20'), 'errRange');
      expect(log.all('POST', '/pause'), isEmpty);

      expect(await c.pause('s1', '2026-10-20', '2026-10-27'), isNull);
      final body =
          jsonDecode(log.last('POST', '/pause')!.body) as Map<String, dynamic>;
      expect(body, {'hold_from': '2026-10-20', 'hold_to': '2026-10-27'});
      c.dispose();
    });

    test(
      'resume guards today and shows the server next_valid_date on 422',
      () async {
        final log = _Log();
        final api = _api(
          MockClient((req) async {
            log.requests.add(req);
            if (req.url.path.endsWith('/resume')) {
              return _json({
                'error': {
                  'code': 'RESUME_TOO_SOON',
                  'message': 'needs notice',
                  'details': {'next_valid_date': '2026-10-25T00:00:00+05:30'},
                },
              }, 422);
            }
            return _standard(req, subs: [_sub(status: 'paused')]);
          }),
        );
        final c = SubscriptionController(api: api);
        final today = ApiClient.dateOnly(DateTime.now());

        expect(await c.resume('s1', today), 'resumeNote');
        expect(log.all('POST', '/resume'), isEmpty);

        final msg = await c.resume(
          's1',
          ApiClient.dateOnly(DateTime.now().add(const Duration(days: 2))),
        );
        expect(msg, contains('2026-10-25'));
        expect(msg, contains('Next available date'));
        c.dispose();
      },
    );

    test('late skip is surfaced instead of silently succeeding', () async {
      final log = _Log();
      final api = _api(
        MockClient((req) async {
          log.requests.add(req);
          if (req.url.path.endsWith('/skips')) {
            return _json({
              'id': 'sk1',
              'sub_id': 's1',
              'date': ApiClient.dateOnly(DateTime.now()),
              'late_skip': true,
            }, 201);
          }
          return _standard(req, subs: [_sub()]);
        }),
      );
      final c = SubscriptionController(api: api);

      expect(await c.skipToday('s1'), 'lateSkip');
      final body =
          jsonDecode(log.last('POST', '/skips')!.body) as Map<String, dynamic>;
      expect(body['date'], ApiClient.dateOnly(DateTime.now()));
      c.dispose();
    });

    test(
      'cancel posts reason + UPI and returns server refund fields',
      () async {
        final log = _Log();
        final api = _api(
          MockClient((req) async {
            log.requests.add(req);
            if (req.url.path.endsWith('/cancel')) {
              return _json({
                'id': 's1',
                'status': 'canceled',
                'message': 'Pickup scheduled.',
                'unused_water_refund_paise': 5000,
                'jars_to_return': 2,
                'deposit_refund_expected_paise': 30000,
              }, 201);
            }
            return _standard(req, subs: [_sub()]);
          }),
        );
        final c = SubscriptionController(api: api);

        final out = await c.cancelSubscription(
          's1',
          'Moving to another city',
          '9876543210@upi',
        );
        expect(out?['message'], 'Pickup scheduled.');
        expect(out?['unused_water_refund_paise'], 5000);
        final body =
            jsonDecode(log.last('POST', '/cancel')!.body)
                as Map<String, dynamic>;
        expect(body['reason'], 'Moving to another city');
        expect(body['upi_id'], '9876543210@upi');
        c.dispose();
      },
    );

    test(
      'payDues posts one stable idempotent intent per dues amount',
      () async {
        final log = _Log();
        var intents = 0;
        final api = _api(
          MockClient((req) async {
            log.requests.add(req);
            if (req.url.path.endsWith('/payments/dues-intent')) {
              intents++;
              return _json({
                'payment': {'id': 'pay$intents'},
                'link': 'upi://pay?pa=test@upi&am=56.00&cu=INR',
                'provider_ref': 'pref_$intents',
              }, 201);
            }
            return _standard(req, subs: [_sub()], dues: 5600);
          }),
        );
        final c = SubscriptionController(api: api);
        await c.load();

        expect((await c.payDues())?['provider_ref'], 'pref_1');
        expect((await c.payDues())?['provider_ref'], 'pref_2');

        final calls = log.all('POST', '/payments/dues-intent');
        expect(calls, hasLength(2));
        final keys = calls.map((r) => _header(r, 'Idempotency-Key')).toList();
        expect(keys.first, isNotEmpty);
        expect(keys.toSet(), hasLength(1)); // same dues → same key → replay
        expect(calls.first.body, '{}');
        c.dispose();
      },
    );
  });

  group('SubscriptionScreen', () {
    testWidgets('empty state opens the builder, estimates and creates', (
      tester,
    ) async {
      final log = _Log();
      final estimates = <Map<String, dynamic>>[];
      http.Request? createReq;
      final api = _api(
        MockClient((req) async {
          log.requests.add(req);
          final p = req.url.path;
          if (p.endsWith('/subscriptions/estimate')) {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            estimates.add(body);
            final qty = (body['qty'] as num).toInt();
            return _json({
              'total': 5000 * qty + 600,
              'water_bill': 5000 * qty,
              'deposit_due': 600,
              'rate_version': 'v1',
            });
          }
          if (p.endsWith('/subscriptions') && req.method == 'POST') {
            createReq = req;
            return _json({
              'id': 's2',
              'first_cycle_estimate': {'total': 10600},
            }, 201);
          }
          return _standard(req);
        }),
      );

      await _pumpScreen(tester, api);
      expect(find.text('No subscription yet'), findsOneWidget);

      await tester.tap(find.text('Build a plan'));
      await tester.pumpAndSettle();
      expect(find.text('Build a monthly plan'), findsOneWidget);
      expect(find.text('First-delivery estimate'), findsOneWidget);
      expect(find.text('Rs 56'), findsOneWidget);
      expect(estimates.single, {'qty': 1, 'sku_mix': 'refill'});

      await tester.tap(find.byTooltip('Add a jar'));
      await tester.pumpAndSettle();
      expect(estimates.last['qty'], 2);
      expect(find.text('Rs 106'), findsOneWidget);

      await tester.ensureVisible(find.text('Start this plan'));
      await tester.tap(find.text('Start this plan'));
      await tester.pumpAndSettle();

      expect(createReq, isNotNull);
      final body = jsonDecode(createReq!.body) as Map<String, dynamic>;
      expect(body['address_id'], 'a1');
      expect(body['qty'], 2);
      expect(body['sku_mix'], 'refill');
      expect(body['window'], '');
      expect(body['schedule_type'], 'daily');
      expect(body['recurrence'], '');
      expect(_header(createReq!, 'Idempotency-Key'), isNotEmpty);
      expect(find.textContaining('Plan started.'), findsOneWidget);
    });

    testWidgets('dues strip pays through the real idempotent intent', (
      tester,
    ) async {
      final log = _Log();
      http.Request? intentReq;
      final api = _api(
        MockClient((req) async {
          log.requests.add(req);
          if (req.url.path.endsWith('/payments/dues-intent')) {
            intentReq = req;
            return _json({
              'payment': {'id': 'p1', 'amount': 5600},
              'link': 'upi://pay?pa=test@upi&am=56.00&cu=INR',
              'provider_ref': 'pref_1',
            }, 201);
          }
          return _standard(req, subs: [_sub(dueToday: 1000)], dues: 5600);
        }),
      );

      await _pumpScreen(tester, api);
      expect(find.text('OUTSTANDING DUES'), findsOneWidget);
      expect(find.text('Rs 56'), findsOneWidget);

      await tester.tap(find.text('Pay dues'));
      await tester.pumpAndSettle();

      expect(find.text('UPI payment request created'), findsOneWidget);
      expect(find.text('Reference: pref_1'), findsOneWidget);
      expect(intentReq, isNotNull);
      expect(intentReq!.method, 'POST');
      expect(intentReq!.body, '{}');
      expect(_header(intentReq!, 'Idempotency-Key'), isNotEmpty);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    });

    testWidgets('401 shows the sign-in copy and retry recovers', (
      tester,
    ) async {
      var listCalls = 0;
      final api = _api(
        MockClient((req) async {
          if (req.method == 'GET' && req.url.path.endsWith('/subscriptions')) {
            listCalls++;
            if (listCalls == 1) {
              return _json({
                'error': {'code': 'UNAUTH', 'message': 'sign in'},
              }, 401);
            }
            return _json({'data': <dynamic>[]});
          }
          return _standard(req);
        }),
      );

      await _pumpScreen(tester, api);
      expect(find.text(subStrings['signedOut']!), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('No subscription yet'), findsOneWidget);
    });

    testWidgets('canceled plan wins over paused and hides actions', (
      tester,
    ) async {
      final api = _api(
        MockClient(
          (req) =>
              _standard(req, subs: [_sub(status: 'paused', canceledAt: true)]),
        ),
      );

      await _pumpScreen(tester, api);
      expect(find.text('Canceled'), findsOneWidget);
      expect(find.text('Paused'), findsNothing);
      expect(find.text('Pause'), findsNothing);
      expect(find.text('Skip today'), findsNothing);
      expect(find.text(subStrings['canceledNote']!), findsOneWidget);
    });
  });
}
