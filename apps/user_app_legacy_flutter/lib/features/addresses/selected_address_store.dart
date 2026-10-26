// SelectedAddressStore: persists the chosen delivery address id so
// Home / checkout / Addresses agree (011_port). Pure ChangeNotifier over
// SharedPreferences — no new state lib. The AddressController owns the
// live selection; this store is only the persistence behind it
// (see AddressController.bindSelection).

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SelectedAddressStore extends ChangeNotifier {
  static const key = 'selected_address_id';

  String? _selectedId;
  String? get selectedId => _selectedId;

  /// Loads the persisted id. Call once at startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(key);
    final next = (id == null || id.isEmpty) ? null : id;
    if (next != _selectedId) {
      _selectedId = next;
      notifyListeners();
    }
  }

  /// Persists + notifies. Null clears the selection.
  Future<void> select(String? id) async {
    final next = (id == null || id.isEmpty) ? null : id;
    if (next == _selectedId) return;
    _selectedId = next;
    final prefs = await SharedPreferences.getInstance();
    if (_selectedId == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, _selectedId!);
    }
    notifyListeners();
  }
}
