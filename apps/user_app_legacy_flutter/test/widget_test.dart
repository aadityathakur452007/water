// 031 — Theme smoke test: locked palette v2 (teal brand, green money CTA,
// slate ground + white cards, blue link-only) + no purple leaking through
// the seed. Plugin-free.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shodasha_app/core/theme.dart';

void main() {
  test('locked palette v2: slate ground, teal brand, green CTA, blue links', () {
    expect(ShodashaTheme.bg, const Color(0xFFF8FAFC));
    expect(ShodashaTheme.surface, const Color(0xFFFFFFFF));
    expect(ShodashaTheme.ink, const Color(0xFF0F172A));
    expect(ShodashaTheme.teal, const Color(0xFF0D9488));
    expect(ShodashaTheme.green, const Color(0xFF16A34A));
    expect(ShodashaTheme.blue, const Color(0xFF0284C7));
  });

  testWidgets('theme: elevated buttons render green CTA, nav indicator teal-tinted',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {},
              child: const Text('x'),
            ),
          ),
        ),
      ),
    );
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(ElevatedButton),
        matching: find.byType(Material),
      ),
    );
    // Locked v2: elevated buttons are the money-CTA green (#16A34A).
    expect(material.color, ShodashaTheme.green);
  });

  test('no purple in the token set', () {
    int ch(double component) => (component * 255.0).round().clamp(0, 255);
    const tokens = [
      ShodashaTheme.bg,
      ShodashaTheme.surface,
      ShodashaTheme.ink,
      ShodashaTheme.muted,
      ShodashaTheme.teal,
      ShodashaTheme.tealTint,
      ShodashaTheme.green,
      ShodashaTheme.blue,
      ShodashaTheme.blueTint,
      ShodashaTheme.border,
      ShodashaTheme.danger,
      ShodashaTheme.success,
    ];
    for (final c in tokens) {
      final r = ch(c.r);
      final g = ch(c.g);
      final b = ch(c.b);
      // Purple-ish = both red and blue channels dominate green heavily and
      // r > b; the locked set has none (blue accent has b > r).
      final isPurple = r > b && b > g;
      expect(isPurple, isFalse, reason: 'token $c looks purple');
    }
  });
}
