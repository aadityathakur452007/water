import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendor_app/core/vendor_locale.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VendorLocaleController.instance.resetForTest('hi');
  });

  test('default language is Hindi and vtr selects Hindi string', () {
    expect(VendorLocaleController.instance.lang, 'hi');
    expect(VendorLocaleController.instance.isHindi, isTrue);
    expect(vtr('कमाई', 'Earnings'), 'कमाई');
  });

  test('switching to English updates lang, isHindi, and vtr', () async {
    bool notified = false;
    VendorLocaleController.instance.addListener(() {
      notified = true;
    });

    await VendorLocaleController.instance.setLanguage('en');

    expect(VendorLocaleController.instance.lang, 'en');
    expect(VendorLocaleController.instance.isHindi, isFalse);
    expect(vtr('कमाई', 'Earnings'), 'Earnings');
    expect(notified, isTrue);

    // Verify persisted in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('vendor_language'), 'en');
  });

  test('init restores saved language preference from SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({'vendor_language': 'en'});

    await VendorLocaleController.instance.init();

    expect(VendorLocaleController.instance.lang, 'en');
    expect(vtr('ड्यूटी', 'Duty'), 'Duty');
  });
}
