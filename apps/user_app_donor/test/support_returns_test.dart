import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/core/api_client.dart';
import 'package:shodasha_donor/features/returns/return_sheet.dart';
import 'package:shodasha_donor/features/support/support_screen.dart';

class _FakeSupportApi extends ApiClient {
  _FakeSupportApi() : super(accessToken: 'test-token');

  @override
  Future<List<dynamic>> listComplaints() async => [];

  @override
  Future<List<dynamic>> listAddresses() async => [];
}

void main() {
  testWidgets('SupportScreen renders complaints section before common questions', (tester) async {
    final api = _FakeSupportApi();

    await tester.pumpWidget(
      MaterialApp(
        home: SupportScreen(api: api),
      ),
    );
    await tester.pumpAndSettle();

    // Verify both sections are rendered
    final complaintsFinder = find.text('Complaints');
    final faqsFinder = find.text('Common questions');
    expect(complaintsFinder, findsOneWidget);
    expect(faqsFinder, findsOneWidget);

    // Verify Complaints section is elevated above Common questions
    final complaintsTop = tester.getTopLeft(complaintsFinder).dy;
    final faqsTop = tester.getTopLeft(faqsFinder).dy;
    expect(complaintsTop, lessThan(faqsTop));

    // Verify complaint entry card is present above FAQs
    expect(find.text('Raise a complaint'), findsOneWidget);
  });

  testWidgets('ReturnSheet renders title with standardized 18px w700 typography', (tester) async {
    final api = _FakeSupportApi();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReturnSheet(api: api, heldJars: 2),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final titleFinder = find.text('Return jars');
    expect(titleFinder, findsOneWidget);

    final titleText = tester.widget<Text>(titleFinder);
    expect(titleText.style?.fontSize, 18);
    expect(titleText.style?.fontWeight, FontWeight.w700);
  });
}

