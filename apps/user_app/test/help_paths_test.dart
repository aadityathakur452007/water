// Phase 4 §4.5 — help paths launch (mock openUrl seam): WhatsApp Open
// attempts wa.me first with clipboard fallback; tanker sheet dials tel:.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/features/booking/home_screen.dart';
import 'package:shodasha_app/features/support/support_screen.dart';
import 'package:url_launcher/url_launcher.dart';

ApiClient _quietApi() => ApiClient(
  client: MockClient((req) async => http.Response('[]', 200)),
  deviceId: 't',
);

void main() {
  group('support complaints error branch', () {
    testWidgets('load failure shows message + retry (never silent none)',
        (tester) async {
      final controller = SupportController(
        // 400 (not retryable) keeps the failure deterministic — the
        // error branch is identical for any ApiException.
        api: ApiClient(
          client: MockClient((req) async => http.Response('bad', 400)),
          deviceId: 't',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: SupportScreen(controller: controller)),
      );
      await tester.pump();
      // Drive the failure after mount (reactive path: notify → rebuild).
      await controller.load();
      expect(controller.status, ComplaintStatus.error);
      await tester.pump();
      // The complaints section sits below the fold in the test viewport —
      // scroll it into view (finders skip offstage sliver children).
      await tester.scrollUntilVisible(
        find.text('Meri shikayatein'),
        300,
      );
      await tester.pump();
      expect(find.text('Dobara try karein'), findsOneWidget);
      controller.dispose();
    });
  });

  group('support WhatsApp', () {
    testWidgets('Kholein attempts wa.me launch (no fallback when it works)', (
      tester,
    ) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SupportScreen(
            controller: SupportController(api: _quietApi()),
            openUrl: (url, {mode = LaunchMode.externalApplication}) async {
              opened.add(url);
              return true;
            },
          ),
        ),
      );
      await tester.tap(find.text('Kholein'));
      await tester.pump();
      expect(opened, hasLength(1));
      expect(opened.single.host, 'wa.me');
      expect(opened.single.path, contains('919302190067'));
      // Launch worked → no copy-fallback snackbar.
      expect(find.text(supportStringsHi['waFail']!), findsNothing);
    });

    testWidgets('failed launch falls back to copy + snackbar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SupportScreen(
            controller: SupportController(api: _quietApi()),
            openUrl: (url, {mode = LaunchMode.externalApplication}) async =>
                false,
          ),
        ),
      );
      await tester.tap(find.text('Kholein'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(supportStringsHi['waFail']!), findsOneWidget);
    });
  });

  group('tanker sheet', () {
    testWidgets('Call button dials tel: support (no placeholder)', (
      tester,
    ) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  showTankerSheet(
                    ctx,
                    openUrl:
                        (url, {mode = LaunchMode.externalApplication}) async {
                          opened.add(url);
                          return true;
                        },
                  );
                });
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Vendor ko call karein'), findsOneWidget);
      // No placeholder number anywhere on the sheet.
      expect(find.textContaining('XXXXXXXXXX'), findsNothing);
      await tester.tap(find.text('Vendor ko call karein'));
      await tester.pump();
      expect(opened, hasLength(1));
      expect(opened.single.scheme, 'tel');
      expect(opened.single.path, contains('919302190067'));
    });
  });
}
