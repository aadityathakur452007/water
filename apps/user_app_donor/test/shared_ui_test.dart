import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/core/constants/app_constants.dart';
import 'package:shodasha_donor/core/theme.dart';
import 'package:shodasha_donor/shared/ui/shared_ui.dart';

Widget _host(Widget child) => MaterialApp(
  theme: buildShodashaTheme(),
  home: Scaffold(body: Center(child: child)),
);

double _contrast(Color a, Color b) {
  final light = a.computeLuminance();
  final dark = b.computeLuminance();
  final high = light > dark ? light : dark;
  final low = light > dark ? dark : light;
  return (high + 0.05) / (low + 0.05);
}

void main() {
  testWidgets('AppButton disabled is inert and keeps 48dp', (tester) async {
    await tester.pumpWidget(
      _host(
        const AppButton(
          label: 'Pay',
          kind: AppButtonKind.money,
          onPressed: null,
          expand: false,
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(AppButton)).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('AppButton busy keeps the fill and blocks taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        AppButton(
          label: 'Pay',
          kind: AppButtonKind.money,
          busy: true,
          expand: false,
          onPressed: () => taps++,
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.getSize(find.byType(AppButton)).height,
      greaterThanOrEqualTo(48),
    );

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(
      button.style!.backgroundColor!.resolve({WidgetState.disabled}),
      ShodashaTheme.greenDark,
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(taps, 0);
  });

  testWidgets('AppButton clamps a short height to 48dp', (tester) async {
    await tester.pumpWidget(
      _host(
        AppButton(label: 'Small', height: 32, expand: false, onPressed: () {}),
      ),
    );

    expect(
      tester.getSize(find.byType(AppButton)).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('AppStateView loading is a skeleton, not a fake value', (
    tester,
  ) async {
    await tester.pumpWidget(_host(AppStateView.loading()));

    expect(find.byKey(const Key('app-state-loading')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('AppStateView empty explains the next action', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        AppStateView.empty(
          title: 'No orders yet',
          message: 'Your first delivery starts here.',
          actionLabel: 'Book water',
          onAction: () => taps++,
        ),
      ),
    );

    expect(find.text('No orders yet'), findsOneWidget);
    expect(find.text('Your first delivery starts here.'), findsOneWidget);

    await tester.tap(find.text('Book water'));
    expect(taps, 1);
  });

  testWidgets('AppStateView error splits network from server wording', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      _host(AppStateView.error(isNetwork: true, onRetry: () => retries++)),
    );

    expect(find.text("You're offline"), findsOneWidget);
    expect(find.text('Server problem'), findsNothing);

    await tester.tap(find.text('Retry'));
    expect(retries, 1);

    await tester.pumpWidget(_host(AppStateView.error(onRetry: () {})));
    expect(find.text('Server problem'), findsOneWidget);
    expect(find.text("You're offline"), findsNothing);
  });

  testWidgets('AppBanner offline and stale both recover in place', (
    tester,
  ) async {
    var offline = 0;
    var stale = 0;

    await tester.pumpWidget(_host(AppBanner.offline(onRetry: () => offline++)));
    expect(find.text("You're offline"), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(offline, 1);

    await tester.pumpWidget(_host(AppBanner.stale(onRetry: () => stale++)));
    expect(find.text('Showing last update'), findsOneWidget);
    await tester.tap(find.text('Refresh'));
    expect(stale, 1);
  });

  testWidgets('StatusPill exposes a readable label, not an enum', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      _host(
        const StatusPill(
          label: 'Delivered',
          tone: StatusPillTone.success,
          icon: Icons.check_circle,
        ),
      ),
    );

    expect(find.text('Delivered'), findsOneWidget);
    expect(find.bySemanticsLabel('Delivered'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('shared primitives compose without overflow', (tester) async {
    await tester.pumpWidget(
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppCard(
              child: AppTextField(
                label: 'Full name',
                helper: 'As on your account',
                counter: '0/60',
                autofillHints: const [AutofillHints.name],
                keyboardType: TextInputType.name,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const SectionHeader(title: 'Orders', padding: EdgeInsets.zero),
            AppIconButton(
              icon: Icons.notifications_outlined,
              tooltip: 'Notifications',
              badge: 3,
              onPressed: () {},
            ),
          ],
        ),
      ),
    );

    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppSheet keeps body and sticky footer reachable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showAppSheet<void>(
                    context: context,
                    builder: (_) => const AppSheet(
                      title: 'Delivery',
                      footer: Text('Sticky footer'),
                      child: SizedBox(height: 600, child: Text('Sheet body')),
                    ),
                  );
                },
                child: const Text('Open sheet'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Delivery'), findsOneWidget);
    expect(find.text('Sheet body'), findsOneWidget);
    expect(find.text('Sticky footer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('locked tokens keep their values and AA contrast', () {
    expect(ShodashaTheme.bg, const Color(0xFFF8FAFC));
    expect(ShodashaTheme.surface, const Color(0xFFFFFFFF));
    expect(ShodashaTheme.ink, const Color(0xFF0F172A));
    expect(ShodashaTheme.muted, const Color(0xFF64748B));
    expect(ShodashaTheme.border, const Color(0xFFE2E8F0));
    expect(ShodashaTheme.teal, const Color(0xFF0D9488));
    expect(ShodashaTheme.tealDark, const Color(0xFF0F766E));
    expect(ShodashaTheme.tealDeep, const Color(0xFF115E59));
    expect(ShodashaTheme.green, const Color(0xFF16A34A));
    expect(ShodashaTheme.greenDark, const Color(0xFF15803D));
    expect(ShodashaTheme.solar, const Color(0xFFFACC15));
    expect(ShodashaTheme.danger, const Color(0xFFB91C1C));
    expect(ShodashaTheme.successDark, const Color(0xFF047857));
    expect(ShodashaTheme.warning, const Color(0xFFB45309));
    expect(ShodashaTheme.link, const Color(0xFF0369A1));
    expect(ShodashaTheme.skeleton, const Color(0xFFE2E8F0));

    expect(AppColors.error, ShodashaTheme.danger);
    expect(AppColors.success, ShodashaTheme.success);
    expect(AppColors.money, ShodashaTheme.green);
    expect(AppConstants.maxContentWidth, 560);
    expect(kMaxContentWidth, 560);

    expect(
      _contrast(ShodashaTheme.surface, ShodashaTheme.greenDark),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(ShodashaTheme.surface, ShodashaTheme.tealDeep),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(ShodashaTheme.surface, ShodashaTheme.tealDark),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(ShodashaTheme.surface, ShodashaTheme.danger),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(ShodashaTheme.surface, ShodashaTheme.muted),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(ShodashaTheme.surface, ShodashaTheme.link),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(ShodashaTheme.surface, ShodashaTheme.warning),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(ShodashaTheme.surface, ShodashaTheme.successDark),
      greaterThanOrEqualTo(4.5),
    );
  });
}
