// SelectedAddressStore persistence (011_port): mock prefs, no device I/O.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shodasha_app/features/addresses/selected_address_store.dart';

void main() {
  test('load/select round-trips the id, empty clears', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SelectedAddressStore();
    await store.load();
    expect(store.selectedId, isNull);

    await store.select('a1');
    expect(store.selectedId, 'a1');

    final again = SelectedAddressStore();
    await again.load();
    expect(again.selectedId, 'a1');

    await again.select(null);
    expect(again.selectedId, isNull);
  });
}
