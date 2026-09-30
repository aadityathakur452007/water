// F5 — Theme smoke test: locked palette (white ground, black ink, water
// blue accents) + no purple leaking through the seed. Plugin-free.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shodasha_app/core/theme.dart';

void main() {
  test('locked palette: white bg, black primary, blue accent-only', () {
    expect(ShodashaTheme.bg, const Color(0xFFFFFFFF));
    expect(ShodashaTheme.ink, const Color(0xFF111111));
    expect(ShodashaTheme.blue, const Color(0xFF0284C7));
  });

  testWidgets('theme: primary buttons render black on white scaffold', (
    tester,
  ) async {
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
    // Locked spec: primary buttons are black (#111), same as ErrorInfo.
    expect(material.color, ShodashaTheme.ink);
  });

  test('no purple in the token set', () {
    int ch(double component) => (component * 255.0).round().clamp(0, 255);
    const tokens = [
      ShodashaTheme.bg,
      ShodashaTheme.ink,
      ShodashaTheme.muted,
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
