import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/core/theme.dart';
import 'package:shodasha_donor/features/legal/privacy_policy_screen.dart';

void main() {
  Widget buildTestWidget() {
    return MaterialApp(
      theme: buildShodashaTheme(),
      home: const PrivacyPolicyScreen(),
    );
  }

  testWidgets('renders DPDP Act 2023 compliance banner and title', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildTestWidget());

    expect(find.text('Privacy Policy & Terms'), findsOneWidget);
    expect(find.text('DPDP Act 2023 Compliant'), findsOneWidget);
    expect(find.text('Privacy at a Glance'), findsOneWidget);
  });

  testWidgets('renders all statutory disclosure sections under Indian laws', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildTestWidget());

    // 1. Data Collection & Purpose
    expect(
      find.text('1. Data We Collect & Purpose Limitation'),
      findsOneWidget,
    );
    expect(find.text('DPDP ACT SEC 5 & 6'), findsOneWidget);

    // 2. Storage & Security
    await tester.scrollUntilVisible(
      find.text('2. Data Storage & Security Safeguards'),
      200,
    );
    expect(
      find.text('2. Data Storage & Security Safeguards'),
      findsOneWidget,
    );
    expect(find.text('AES-256 · TLS 1.3'), findsOneWidget);

    // 3. Breach & Incident Response
    await tester.scrollUntilVisible(
      find.text('3. Data Breach & Incident Response'),
      200,
    );
    expect(
      find.text('3. Data Breach & Incident Response'),
      findsOneWidget,
    );
    expect(find.text('CERT-IN & DPDP ACT SEC 8(6)'), findsOneWidget);

    // 4. ₹650 Jar Terms
    await tester.scrollUntilVisible(
      find.text('4. ₹650 Reusable Jar Asset Terms'),
      200,
    );
    expect(
      find.text('4. ₹650 Reusable Jar Asset Terms'),
      findsOneWidget,
    );

    // 5. User Rights
    await tester.scrollUntilVisible(
      find.text('5. Your Rights as a Data Principal'),
      200,
    );
    expect(
      find.text('5. Your Rights as a Data Principal'),
      findsOneWidget,
    );

    // 6. Grievance Officer
    await tester.scrollUntilVisible(
      find.text('6. Grievance Redressal Officer'),
      200,
    );
    expect(
      find.text('6. Grievance Redressal Officer'),
      findsOneWidget,
    );
    expect(find.text('STATUTORY REDRESSAL'), findsOneWidget);

    // 7. Account deletion action
    await tester.scrollUntilVisible(
      find.text('Request Account & Data Deletion'),
      200,
    );
    expect(find.text('Request Account & Data Deletion'), findsOneWidget);
  });

  testWidgets('opens account deletion sheet when delete button is tapped', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildTestWidget());

    await tester.scrollUntilVisible(
      find.text('Request Account & Data Deletion'),
      200,
    );
    await tester.tap(find.text('Request Account & Data Deletion'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Account & Data'), findsOneWidget);
    expect(find.textContaining('Under the DPDP Act 2023'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });
}
