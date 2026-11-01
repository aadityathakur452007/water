import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single source of truth for Vendor App language localization (DEF-11, ADR-164).
/// Defaults to Hindi ('hi') per Decision 1 in 23-owner-decisions.md, with English ('en') optional.
class VendorLocaleController extends ChangeNotifier {
  VendorLocaleController._();
  static final VendorLocaleController instance = VendorLocaleController._();

  static const String prefKey = 'vendor_language';

  String _lang = 'hi';
  String get lang => _lang;
  bool get isHindi => _lang == 'hi';

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(prefKey);
      if (saved == 'en' || saved == 'hi') {
        _lang = saved!;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setLanguage(String lang) async {
    if (_lang == lang || (lang != 'hi' && lang != 'en')) return;
    _lang = lang;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKey, lang);
    } catch (_) {}
  }

  @visibleForTesting
  void resetForTest([String lang = 'hi']) {
    _lang = lang;
    notifyListeners();
  }
}

/// Convenience translator returning clean, unslashed text based on active vendor locale.
String vtr(String hi, String en) {
  return VendorLocaleController.instance.isHindi ? hi : en;
}
