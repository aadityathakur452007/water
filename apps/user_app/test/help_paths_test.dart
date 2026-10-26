// S8 help paths: load failure + retry, WhatsApp launch/clipboard fallback,
// complaint POST payload/headers, 422 window-closed → WhatsApp, and the
// no-money copy law. Plugin-free (mocked http + injected URL opener).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/core/theme.dart';
import 'package:shodasha_app/features/support/support_controller.dart';
import 'package:shodasha_app/features/support/support_screen.dart';
import 'package:url_launcher/url_launcher.dart';

ApiClient _api(MockClient client) => ApiClient(
  client: client,
  accessToken: 'tok',
  deviceId: 'dev',
  baseUrl: 'http://localhost:8787/v1',
);

Widget _app(Widget home) =>
    MaterialApp(theme: buildShodashaTheme(), home: home);

void main() {
  group('support complaints', () {
    testWidgets('load failure shows message + retry recovers to empty', (
      tester,
    ) async {
      var calls = 0;
      final client = MockClient((req) async {
        calls += 1;
        if (calls == 1) return http.Response('bad', 400);
        return http.Response('[]', 200);
      });
      final controller = SupportController(api: _api(client));
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(SupportScreen(api: _api(client), controller: controller)),
      );
      await tester.pump();
      await controller.load();
      await tester.pump();

      expect(controller.status, ComplaintStatus.error);
      expect(controller.errorMessage, supportStrings['loadError']);
      final errorText = find.text(supportStrings['loadError']!);
      await tester.scrollUntilVisible(errorText, 300);
      await tester.pump();
      expect(errorText, findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(controller.status, ComplaintStatus.loaded);
      expect(controller.items, isEmpty);
      final emptyText = find.text(
        'No complaints yet. If an order goes wrong, raise one above.',
      );
      await tester.scrollUntilVisible(emptyText, 300);
      expect(emptyText, findsOneWidget);
    });

    testWidgets('unauthorized load maps to session-expired copy', (
      tester,
    ) async {
      final controller = SupportController(
        api: _api(
          MockClient(
            (req) async => http.Response(
              jsonEncode({
                'error': {'code': 'UNAUTH', 'message': 'expired'},
              }),
              401,
            ),
          ),
        ),
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.status, ComplaintStatus.error);
      expect(controller.errorMessage, supportStrings['sessionExpired']);
    });

    testWidgets('submit posts contract payload with auth headers', (
      tester,
    ) async {
      final requests = <http.Request>[];
      final client = MockClient((req) async {
        requests.add(req);
        if (req.method == 'POST') return http.Response('{}', 201);
        return http.Response('[]', 200);
      });
      final controller = SupportController(api: _api(client));
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(SupportScreen(api: _api(client), controller: controller)),
      );
      await tester.pump();

      final newButton = find.text('New');
      await tester.scrollUntilVisible(newButton, 300);
      await tester.ensureVisible(newButton);
      await tester.pumpAndSettle();
      await tester.tap(newButton);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('complaint-order')),
        'ORD-123',
      );
      await tester.enterText(
        find.byKey(const Key('complaint-text')),
        'The jar was leaking.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('complaint-submit')));
      await tester.pumpAndSettle();

      final post = requests.singleWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/complaints'),
      );
      expect(
        post.headers['Authorization'] ?? post.headers['authorization'],
        'Bearer tok',
      );
      expect(post.headers['X-Device-Id'] ?? post.headers['x-device-id'], 'dev');
      expect(jsonDecode(post.body), {
        'order_id': 'ORD-123',
        'reason_code': 'water_quality',
        'text': 'The jar was leaking.',
      });
      // Legacy bug: busy stayed true after success.
      expect(controller.busy, isFalse);
      expect(find.text('Complaint submitted.'), findsOneWidget);
    });

    testWidgets('server 422 offers the WhatsApp help path', (tester) async {
      final opened = <Uri>[];
      final client = MockClient((req) async {
        if (req.method == 'POST') {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'COMPLAINT_WINDOW_CLOSED',
                'message': 'The complaint window has closed.',
              },
            }),
            422,
          );
        }
        return http.Response('[]', 200);
      });
      final controller = SupportController(api: _api(client));
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(
          SupportScreen(
            api: _api(client),
            controller: controller,
            openUrl: (url, {mode = LaunchMode.externalApplication}) async {
              opened.add(url);
              return true;
            },
          ),
        ),
      );
      await tester.pump();

      final newButton = find.text('New');
      await tester.scrollUntilVisible(newButton, 300);
      await tester.ensureVisible(newButton);
      await tester.pumpAndSettle();
      await tester.tap(newButton);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('complaint-order')), 'ORD-9');
      await tester.enterText(
        find.byKey(const Key('complaint-text')),
        'Water tasted strange.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('complaint-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Complaint window closed'), findsOneWidget);
      await tester.tap(find.text('WhatsApp us'));
      await tester.pumpAndSettle();

      expect(opened, hasLength(1));
      expect(opened.single.host, 'wa.me');
      expect(opened.single.path, '/919302190067');
    });
  });

  group('support WhatsApp', () {
    testWidgets('opens wa.me with digits from kSupportPhone', (tester) async {
      final opened = <Uri>[];
      final client = MockClient((req) async => http.Response('[]', 200));
      final controller = SupportController(api: _api(client));
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(
          SupportScreen(
            api: _api(client),
            controller: controller,
            orderContext: 'Order A3F9 is late',
            openUrl: (url, {mode = LaunchMode.externalApplication}) async {
              opened.add(url);
              return true;
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Chat on WhatsApp'));
      await tester.pump();

      expect(opened, hasLength(1));
      final uri = opened.single;
      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/919302190067');
      expect(uri.queryParameters['text'], 'Order A3F9 is late');
      // Successful launch → no clipboard fallback snackbar.
      expect(find.text('WhatsApp did not open — number copied.'), findsNothing);
    });

    testWidgets('failed launch copies the number + shows fallback', (
      tester,
    ) async {
      final client = MockClient((req) async => http.Response('[]', 200));
      final controller = SupportController(api: _api(client));
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(
          SupportScreen(
            api: _api(client),
            controller: controller,
            openUrl: (url, {mode = LaunchMode.externalApplication}) async =>
                false,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Chat on WhatsApp'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('WhatsApp did not open — number copied.'),
        findsOneWidget,
      );
    });
  });

  group('support copy', () {
    testWidgets('never renders money or delivery promises', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final client = MockClient((req) async {
        if (req.method == 'GET') {
          return http.Response(
            jsonEncode([
              {
                'id': 'c1',
                'order_id': 'A3F9',
                'reason_code': 'deposit_dispute',
                'text': 'Deposit not refunded yet',
                'status': 'progress',
              },
            ]),
            200,
          );
        }
        return http.Response('{}', 200);
      });
      final controller = SupportController(api: _api(client));
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(SupportScreen(api: _api(client), controller: controller)),
      );
      await controller.load();
      await tester.pumpAndSettle();

      final copy = tester
          .widgetList<Text>(find.byType(Text, skipOffstage: false))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .join('\n');
      expect(copy, isNot(contains('₹')));
      expect(RegExp(r'\b150\b').hasMatch(copy), isFalse);
      expect(copy, isNot(contains('48 hour')));
      expect(copy, isNot(contains('48-hour')));
      expect(copy, contains('Deposit dispute'));
    });
  });
}
