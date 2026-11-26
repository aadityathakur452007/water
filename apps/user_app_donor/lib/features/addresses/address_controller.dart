part of 'address_screen.dart';

enum _ServiceCheck { unchecked, checking, serviceable, notServiceable, unknown }

enum AddrType { home, office }

/// Two-line bar detail: house/street/area when present, else the saved line.
String addressDetailLine(AddressEntry a) {
  final parts = [a.house, a.street, a.area]
      .whereType<String>()
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.isNotEmpty) return parts.join(', ');
  return a.addressLine;
}

@immutable
class AddressEntry {
  const AddressEntry({
    required this.id,
    required this.label,
    required this.type,
    required this.phone,
    required this.pincode,
    required this.addressLine,
    this.landmark,
    this.lift = false,
    this.isDefault = false,
    this.lat = 23.2599,
    this.lng = 77.4126,
    this.house,
    this.street,
    this.area,
  });

  final String id;
  final String label;
  final AddrType type;
  final String phone;
  final String pincode;
  final String addressLine;
  final String? landmark;
  final bool lift;
  final bool isDefault;

  final String? house;
  final String? street;
  final String? area;

  /// Map pin coordinates (defaults to central Bhopal to satisfy backend non-null).
  final double lat;
  final double lng;

  /// Wire payload. `formatted` is the server's address text; the extra
  /// fields are the full-format columns the server also stores.
  Map<String, dynamic> toApi() => {
        'label': label,
        'type': type == AddrType.home ? 'home' : 'office',
        'formatted': addressLine,
        'pincode': pincode,
        'landmark': landmark,
        'lift_flag': lift,
        'lat': (lat == 0) ? 23.2599 : lat,
        'lng': (lng == 0) ? 77.4126 : lng,
        'house': house,
        'street': street,
        'area': area,
        'phone': phone.isEmpty ? null : phone,
      };

  static AddressEntry fromApi(Map<String, dynamic> j) => AddressEntry(
        id: (j['id'] ?? '') as String,
        label: (j['label'] ?? '') as String,
        type: j['type'] == 'office' ? AddrType.office : AddrType.home,
        phone: (j['phone'] ?? '') as String,
        pincode: (j['pincode'] ?? '') as String,
        addressLine: (j['address_line'] ?? j['formatted'] ?? '') as String,
        landmark: j['landmark'] as String?,
        lift: (j['lift_flag'] ?? j['has_lift'] ?? false) as bool,
        isDefault: (j['is_default'] ?? false) as bool,
        lat: ((j['lat'] ?? 23.2599) as num).toDouble(),
        lng: ((j['lng'] ?? 77.4126) as num).toDouble(),
        house: j['house'] as String?,
        street: j['street'] as String?,
        area: j['area'] as String?,
      );
}

enum AddrStatus { initial, loading, loaded, error }

/// Controller over GET/POST/PATCH/DELETE /addresses (owner-scoped).
class AddressController extends ChangeNotifier {
  AddressController({required this._api});

  final ApiClient _api;

  AddrStatus _status = AddrStatus.initial;
  List<AddressEntry> _items = [];
  String? _errorMessage;
  bool _busy = false;

  /// User boundary: bumped by [reset]; async completions from a previous
  /// account are discarded.
  int _generation = 0;

  AddrStatus get status => _status;
  List<AddressEntry> get items => List.unmodifiable(_items);
  String? get errorMessage => _errorMessage;
  bool get busy => _busy;

  /// Live delivery selection: Home / checkout / Addresses agree.
  String? _selectedId;
  SelectedAddressStore? _store;

  String? get selectedId => _selectedId;

  /// Binds persistence (call once after store.load).
  void bindSelection(SelectedAddressStore store) {
    _store = store;
    final persisted = store.selectedId;
    if (persisted != null && _items.any((a) => a.id == persisted)) {
      _selectedId = persisted;
      _notify();
    }
  }

  /// Selects the delivery address (tap a row). Writes through to the store.
  void select(String? id) {
    if (id == _selectedId) return;
    _selectedId = (id == null || id.isEmpty) ? null : id;
    _store?.select(_selectedId);
    _notify();
  }

  /// Resolves the delivery address: selected (when still saved) → default →
  /// first → null.
  AddressEntry? resolve() {
    if (_items.isEmpty) return null;
    for (final a in _items) {
      if (a.id == _selectedId) return a;
    }
    for (final a in _items) {
      if (a.isDefault) return a;
    }
    return _items.first;
  }

  Future<void> load() async {
    if (_status == AddrStatus.loading) return;
    _status = AddrStatus.loading;
    _errorMessage = null;
    _notify();
    final gen = _generation;
    try {
      final raw = await _api.listAddresses();
      if (gen != _generation) return; // reset mid-flight (logout/user switch)
      _items = raw
          .whereType<Map<String, dynamic>>()
          .map(AddressEntry.fromApi)
          .toList();
      _status = AddrStatus.loaded;
      // Adopt a persisted selection that arrived before the items did.
      if (_selectedId == null) {
        final persisted = _store?.selectedId;
        if (persisted != null && _items.any((a) => a.id == persisted)) {
          _selectedId = persisted;
        }
      }
    } on ApiException catch (e) {
      if (gen != _generation) return;
      _status = AddrStatus.error;
      _errorMessage = e.isOffline
          ? addressStrings['offline']
          : e.isServerError
              ? addressStrings['server']
              : addressStrings['loadFailed'];
    } catch (_) {
      if (gen != _generation) return;
      _status = AddrStatus.error;
      _errorMessage = addressStrings['loadFailed'];
    }
    _notify();
  }

  /// User boundary: clears rows + selection and invalidates in-flight
  /// requests so the next account never sees the previous user's addresses.
  void reset() {
    _generation++;
    _selectedId = null;
    _store?.select(null);
    _items = [];
    _status = AddrStatus.initial;
    _errorMessage = null;
    _busy = false;
    _notify();
  }

  Future<bool> save(AddressEntry entry, {bool isNew = true}) async {
    _busy = true;
    _errorMessage = null;
    _notify();
    final gen = _generation;
    try {
      final body = entry.toApi();
      final saved = isNew
          ? AddressEntry.fromApi(await _api.createAddress(body))
          : AddressEntry.fromApi(await _api.patchAddress(entry.id, body));
      if (gen != _generation) return true;
      final idx = _items.indexWhere((a) => a.id == saved.id);
      if (idx >= 0) {
        _items[idx] = saved;
      } else {
        _items.add(saved);
      }
      select(saved.id); // newly saved address becomes the delivery address
      return true;
    } on ApiException catch (e) {
      if (gen != _generation) return false;
      _errorMessage = e.statusCode == 409
          ? addressStrings['editBlockedBody']
          : e.isOffline
              ? addressStrings['offline']
              : e.isServerError
                  ? addressStrings['server']
                  : addressStrings['loadFailed'];
      return false;
    } catch (_) {
      if (gen != _generation) return false;
      _errorMessage = addressStrings['loadFailed'];
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<bool> delete(String id) async {
    _busy = true;
    _notify();
    final gen = _generation;
    try {
      await _api.deleteAddress(id);
      if (gen != _generation) return true;
      _items.removeWhere((a) => a.id == id);
      if (_selectedId == id) select(null);
      return true;
    } on ApiException catch (e) {
      if (gen != _generation) return false;
      _errorMessage = e.statusCode == 409
          ? addressStrings['deleteBlockedBody']
          : e.isOffline
              ? addressStrings['offline']
              : e.isServerError
                  ? addressStrings['server']
                  : addressStrings['loadFailed'];
      return false;
    } catch (_) {
      if (gen != _generation) return false;
      _errorMessage = addressStrings['offline'];
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// GET /windows?pincode → serviceable flag. Null when the check itself
  /// failed (offline / unknown), so the UI never invents a yes/no.
  Future<bool?> checkServiceable(String pincode) async {
    if (!isValidPincode(pincode)) return null;
    try {
      final res = await _api.windows(pincode: pincode.trim());
      final value = res['serviceable'];
      return value is bool ? value : null;
    } catch (_) {
      return null;
    }
  }

  void _notify() {
    if (!disposed) notifyListeners();
  }

  @protected
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

/// Address entry gate: authed users go straight to Addresses; guests go
/// through the supplied auth flow first and the gate re-checks live state.
Future<void> openAddressesGated(
  BuildContext context, {
  required bool Function() isAuthed,
  required Future<bool> Function(BuildContext context) ensureAuth,
  required void Function(BuildContext context) openAddresses,
}) async {
  if (!isAuthed()) {
    final ok = await ensureAuth(context);
    if (!context.mounted) return;
    if (!ok || !isAuthed()) return;
  }
  if (!context.mounted) return;
  openAddresses(context);
}

/// Addresses page (list + add/edit sheet + gates).
