// Addresses: list + add/edit form, serviceability check, selection store.
//
// Contract §4.3: GET/POST/PATCH/DELETE /addresses. `formatted` carries the
// typed address line; house/street/area/phone ride as their own fields.
// 409 means an undispatched order holds the address — the message is shown,
// never swallowed.
//
// The entry gate re-checks live auth after the login flow so a guest can
// never land on a server 401 after filling the form.
//
// ignore_for_file: prefer_initializing_formals
// WHY: the public `api:` parameter must stay public while the field is
// private; a private initializing formal is unusable from other libraries.

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../core/location_service.dart';
import '../../core/theme.dart';
import 'map_picker.dart' show pickMapPin;
import 'selected_address_store.dart';

/// English copy for the v1 app (ADR-120).
const Map<String, String> addressStrings = {
  'title': 'SAVED ADDRESSES',
  'addTitle': 'New address',
  'editTitle': 'Edit address',
  'emptyTitle': 'No addresses yet',
  'emptyHint': 'Add your first address — deliveries will come here.',
  'addFirst': 'Add address',
  'labelField': 'Name (home/office)',
  'typeHome': 'Home',
  'typeOffice': 'Office',
  'phone': 'Phone',
  'pincode': 'Pincode',
  'addressLine': 'Full address',
  'house': 'House / Flat no.',
  'street': 'Street',
  'area': 'Area / Locality',
  'landmark': 'Landmark (optional)',
  'lift': 'Lift available',
  'save': 'Save address',
  'saving': 'Saving…',
  'delete': 'Delete',
  'deleteConfirmTitle': 'Delete this address?',
  'deleteConfirmBody': 'This address will be removed permanently.',
  'deleteBlockedBody':
      'This address has active orders or subscriptions. Complete or '
      'cancel them first, or contact support.',
  'deleteYes': 'Yes, delete',
  'deleteNo': 'Keep it',
  'defaultTick': 'Default',
  'errPincode': 'Enter a 6-digit pincode',
  'errLine': 'Enter the full address',
  'errLabel': 'Enter a name',
  'errOfficeBulk': 'Office addresses use bulk rules (monthly bill).',
  'errMap': 'Place a pin on the map to continue.',
  'editBlockedTitle': "Can't edit right now",
  'editBlockedBody':
      'An undispatched order uses this address. Let it '
      'deliver first, or contact support.',
  'loadFailed': 'Could not load addresses.',
  'offline': 'No internet — check your connection and retry.',
  'saved': 'Address saved',
  'deleted': 'Address deleted',
  'retry': 'Retry',
  'savedHeader': 'SAVED DELIVERY ADDRESSES',
  'savedCount': 'saved',
  'serviceNo':
      "We don't deliver to this pincode yet. You can still save it "
      "and we'll let you know when we do.",
  'serviceUnknown':
      "Couldn't verify delivery to this pincode. You can still "
      'save it — the server confirms serviceability at order time.',
  'discardTitle': 'Discard changes?',
  'discardBody': 'Your changes to this address will be lost.',
  'discardKeep': 'Keep editing',
  'discardConfirm': 'Discard',
};

/// Pincode: exactly 6 digits, first non-zero (Indian postal norms).
bool isValidPincode(String v) => RegExp(r'^[1-9][0-9]{5}$').hasMatch(v);

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
    this.lat = 0,
    this.lng = 0,
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

  /// Map pin (the backend rejects 0,0 — the form gates on a real pin).
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
    'lat': lat,
    'lng': lng,
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
    lift: (j['lift_flag'] ?? false) as bool,
    isDefault: (j['is_default'] ?? false) as bool,
    lat: ((j['lat'] ?? 0) as num).toDouble(),
    lng: ((j['lng'] ?? 0) as num).toDouble(),
    house: j['house'] as String?,
    street: j['street'] as String?,
    area: j['area'] as String?,
  );
}

enum AddrStatus { initial, loading, loaded, error }

/// Controller over GET/POST/PATCH/DELETE /addresses (owner-scoped).
class AddressController extends ChangeNotifier {
  AddressController({required ApiClient api}) : _api = api;

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
      _errorMessage = e.isNetwork
          ? addressStrings['offline']
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
          : e.isNetwork
          ? addressStrings['offline']
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
          : e.isNetwork
          ? addressStrings['offline']
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
      final res = await _api.windows(pincode: pincode);
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
class AddressScreen extends StatefulWidget {
  const AddressScreen({super.key, required this.controller});

  final AddressController controller;

  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.controller.status == AddrStatus.initial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.controller.load();
      });
    }
  }

  Future<void> _openForm({AddressEntry? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ShodashaTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ShodashaTheme.radiusSheet),
        ),
      ),
      builder: (_) =>
          _AddressFormSheet(controller: widget.controller, existing: existing),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(addressStrings['saved']!)));
    }
  }

  Future<void> _confirmDelete(AddressEntry a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: ShodashaTheme.shape,
        title: Text(addressStrings['deleteConfirmTitle']!),
        content: Text(addressStrings['deleteConfirmBody']!),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(addressStrings['deleteNo']!),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ShodashaTheme.danger,
              foregroundColor: ShodashaTheme.surface,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(addressStrings['deleteYes']!),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = await widget.controller.delete(a.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          done
              ? addressStrings['deleted']!
              : (widget.controller.errorMessage ?? addressStrings['offline']!),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      backgroundColor: ShodashaTheme.bg,
      appBar: AppBar(title: Text(addressStrings['title']!)),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          if (c.status == AddrStatus.loading && c.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (c.status == AddrStatus.error && c.items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 32,
                      color: ShodashaTheme.danger,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      c.errorMessage ?? addressStrings['loadFailed']!,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: c.load,
                      child: Text(addressStrings['retry']!),
                    ),
                  ],
                ),
              ),
            );
          }
          if (c.items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 40,
                      color: ShodashaTheme.teal,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      addressStrings['emptyTitle']!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      addressStrings['emptyHint']!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: ShodashaTheme.muted,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ShodashaTheme.teal,
                        foregroundColor: ShodashaTheme.surface,
                      ),
                      onPressed: () => _openForm(),
                      child: Text(addressStrings['addFirst']!),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: c.load,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: c.items.length + 2,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          addressStrings['savedHeader']!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: ShodashaTheme.muted,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          '${c.items.length} ${addressStrings['savedCount']!}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: ShodashaTheme.teal,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                if (i == c.items.length + 1) {
                  return ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ShodashaTheme.teal,
                      foregroundColor: ShodashaTheme.surface,
                    ),
                    onPressed: () => _openForm(),
                    child: Text(addressStrings['addFirst']!),
                  );
                }
                final a = c.items[i - 1];
                final selected =
                    c.selectedId == a.id ||
                    (c.selectedId == null && c.resolve()?.id == a.id);
                return InkWell(
                  onTap: () => c.select(a.id),
                  borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: selected
                          ? ShodashaTheme.teal.withValues(alpha: 0.08)
                          : ShodashaTheme.surface,
                      border: Border.all(
                        color: selected
                            ? ShodashaTheme.teal
                            : ShodashaTheme.border,
                        width: selected ? 1.5 : 1,
                      ),
                      borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              a.type == AddrType.office
                                  ? Icons.apartment_rounded
                                  : Icons.home_rounded,
                              size: 22,
                              color: selected
                                  ? ShodashaTheme.teal
                                  : ShodashaTheme.muted,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                a.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                  color: ShodashaTheme.ink,
                                ),
                              ),
                            ),
                            if (selected)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Icon(
                                  Icons.check_circle,
                                  size: 20,
                                  color: ShodashaTheme.teal,
                                ),
                              ),
                            if (a.isDefault)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? ShodashaTheme.surface
                                      : ShodashaTheme.tealTint,
                                  borderRadius: BorderRadius.circular(
                                    ShodashaTheme.radius,
                                  ),
                                ),
                                child: Text(
                                  addressStrings['defaultTick']!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: ShodashaTheme.teal,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${a.addressLine}, ${a.pincode}',
                          style: const TextStyle(
                            color: ShodashaTheme.muted,
                            fontSize: 13,
                          ),
                        ),
                        if (a.landmark != null && a.landmark!.isNotEmpty)
                          Text(
                            a.landmark!,
                            style: const TextStyle(
                              color: ShodashaTheme.muted,
                              fontSize: 13,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => _openForm(existing: a),
                              child: const Text('Edit'),
                            ),
                            TextButton(
                              onPressed: () => _confirmDelete(a),
                              child: Text(
                                addressStrings['delete']!,
                                style: const TextStyle(
                                  color: ShodashaTheme.danger,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Add/edit form sheet (name/type/phone → address → map pin).
class _AddressFormSheet extends StatefulWidget {
  const _AddressFormSheet({required this.controller, this.existing});

  final AddressController controller;
  final AddressEntry? existing;

  @override
  State<_AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends State<_AddressFormSheet> {
  late final TextEditingController _label;
  late final TextEditingController _phone;
  late final TextEditingController _pincode;
  late final TextEditingController _line;
  late final TextEditingController _landmark;
  late final TextEditingController _house;
  late final TextEditingController _street;
  late final TextEditingController _area;
  late AddrType _type;
  bool _lift = false;
  bool _touched = false;
  bool _locating = false;
  bool _allowPop = false;
  String? _locateError;
  String? _serviceNote;

  final _labelFocus = FocusNode();
  final _pincodeFocus = FocusNode();
  final _lineFocus = FocusNode();

  int _step = 0;
  String? _saveError;

  double? _lat;
  double? _lng;

  bool get _isNew => widget.existing == null;

  /// True when any field differs from the row being edited (new = blank).
  bool get _dirty {
    final e = widget.existing;
    final hasPin = e != null && (e.lat != 0 || e.lng != 0);
    return _label.text != (e?.label ?? '') ||
        _phone.text != (e?.phone ?? '') ||
        _pincode.text != (e?.pincode ?? '') ||
        _line.text != (e?.addressLine ?? '') ||
        _landmark.text != (e?.landmark ?? '') ||
        _house.text != (e?.house ?? '') ||
        _street.text != (e?.street ?? '') ||
        _area.text != (e?.area ?? '') ||
        _type != (e?.type ?? AddrType.home) ||
        _lift != (e?.lift ?? false) ||
        _lat != (hasPin ? e.lat : null) ||
        _lng != (hasPin ? e.lng : null);
  }

  Future<bool> _confirmDiscard() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: ShodashaTheme.shape,
        title: Text(addressStrings['discardTitle']!),
        content: Text(addressStrings['discardBody']!),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(foregroundColor: ShodashaTheme.muted),
            child: Text(addressStrings['discardKeep']!),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(addressStrings['discardConfirm']!),
          ),
        ],
      ),
    );
    return leave == true;
  }

  Future<void> _close() async {
    if (!_dirty) {
      Navigator.of(context).pop(false);
      return;
    }
    final leave = await _confirmDiscard();
    if (!mounted || !leave) return;
    _popWith(false);
  }

  /// PopScope's canPop is a build-time value; flag it, rebuild, then pop on
  /// the next frame so the guarded route allows the programmatic pop.
  void _popWith(bool result) {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _label = TextEditingController(text: e?.label ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _pincode = TextEditingController(text: e?.pincode ?? '');
    _line = TextEditingController(text: e?.addressLine ?? '');
    _landmark = TextEditingController(text: e?.landmark ?? '');
    _house = TextEditingController(text: e?.house ?? '');
    _street = TextEditingController(text: e?.street ?? '');
    _area = TextEditingController(text: e?.area ?? '');
    _type = e?.type ?? AddrType.home;
    _lift = e?.lift ?? false;
    if (e != null && (e.lat != 0 || e.lng != 0)) {
      _lat = e.lat;
      _lng = e.lng;
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _phone.dispose();
    _pincode.dispose();
    _line.dispose();
    _landmark.dispose();
    _house.dispose();
    _street.dispose();
    _area.dispose();
    _labelFocus.dispose();
    _pincodeFocus.dispose();
    _lineFocus.dispose();
    super.dispose();
  }

  bool get _pinOk => isValidPincode(_pincode.text);
  bool get _labelOk => _label.text.trim().isNotEmpty;
  bool get _lineOk => _line.text.trim().length >= 6;
  bool get _mapOk => _lat != null && _lng != null;
  bool get _valid => _pinOk && _labelOk && _lineOk && _mapOk;

  bool _stepOk(int step) {
    switch (step) {
      case 0:
        return _labelOk;
      case 1:
        return _pinOk && _lineOk;
      default:
        return _valid;
    }
  }

  Future<void> _onContinue() async {
    setState(() => _touched = true);
    if (_step < 2) {
      if (!_stepOk(_step)) return;
      if (_step == 1) {
        final serviceable = await widget.controller.checkServiceable(
          _pincode.text.trim(),
        );
        if (!mounted) return;
        setState(() {
          _serviceNote = serviceable == false
              ? addressStrings['serviceNo']
              : serviceable == null
              ? addressStrings['serviceUnknown']
              : null;
        });
      }
      setState(() => _step++);
      return;
    }
    await _save();
  }

  Future<void> _save() async {
    setState(() {
      _touched = true;
      _saveError = null;
    });
    if (!_labelOk) {
      _labelFocus.requestFocus();
      return;
    }
    if (!_pinOk) {
      _pincodeFocus.requestFocus();
      return;
    }
    if (!_lineOk) {
      _lineFocus.requestFocus();
      return;
    }
    if (!_valid) return;
    FocusScope.of(context).unfocus();
    String? clean(TextEditingController t) {
      final v = t.text.trim();
      return v.isEmpty ? null : v;
    }

    final ok = await widget.controller.save(
      AddressEntry(
        id: widget.existing?.id ?? '',
        label: _label.text.trim(),
        type: _type,
        phone: _phone.text.trim(),
        pincode: _pincode.text.trim(),
        addressLine: _line.text.trim(),
        landmark: _landmark.text.trim().isEmpty ? null : _landmark.text.trim(),
        lift: _lift,
        isDefault: widget.existing?.isDefault ?? false,
        lat: _lat ?? 0,
        lng: _lng ?? 0,
        house: clean(_house),
        street: clean(_street),
        area: clean(_area),
      ),
      isNew: _isNew,
    );
    if (!mounted) return;
    if (ok) {
      _popWith(true);
    } else {
      setState(
        () => _saveError =
            widget.controller.errorMessage ?? addressStrings['offline'],
      );
    }
  }

  /// Current-location prefill: fix + reverse-geocode → pin + fields.
  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _locateError = null;
    });
    try {
      final loc = await LocationService().resolveCurrentAddress();
      if (!mounted) return;
      setState(() {
        _lat = loc.latitude;
        _lng = loc.longitude;
        if (loc.street != null && loc.street!.isNotEmpty) {
          _street.text = loc.street!;
        }
        if (loc.area != null && loc.area!.isNotEmpty) {
          _area.text = loc.area!;
        }
        if (loc.displayLabel.isNotEmpty) {
          _line.text = loc.displayLabel;
        }
        if (loc.postalCode != null && loc.postalCode!.isNotEmpty) {
          _pincode.text = loc.postalCode!;
        }
      });
    } on LocationError catch (e) {
      if (!mounted) return;
      if (e.type == LocationErrorType.reverseGeocodeFailed) {
        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 10),
            ),
          );
          if (!mounted) return;
          setState(() {
            _lat = pos.latitude;
            _lng = pos.longitude;
            if (_line.text.trim().isEmpty) {
              _line.text =
                  'GPS (${pos.latitude.toStringAsFixed(4)}, '
                  '${pos.longitude.toStringAsFixed(4)})';
            }
            _locateError = null;
          });
          return;
        } catch (_) {
          // Fall through to the typed message.
        }
      }
      setState(() => _locateError = e.userMessage);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.9;
    return PopScope(
      canPop: _allowPop || !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !mounted || widget.controller.busy) return;
        final leave = await _confirmDiscard();
        if (!leave || !mounted) return;
        _popWith(false);
      },
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SizedBox(
            height: sheetHeight,
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isNew
                            ? addressStrings['addTitle']!
                            : addressStrings['editTitle']!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: ShodashaTheme.muted,
                      ),
                      tooltip: 'Close',
                      onPressed: c.busy ? null : _close,
                    ),
                  ],
                ),
                if (_type == AddrType.office) ...[
                  const SizedBox(height: 2),
                  Text(
                    addressStrings['errOfficeBulk']!,
                    style: const TextStyle(
                      color: ShodashaTheme.blue,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Expanded(
                  child: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => Stepper(
                      type: StepperType.vertical,
                      currentStep: _step,
                      onStepTapped: (i) => setState(() => _step = i),
                      onStepContinue: _onContinue,
                      onStepCancel: () {
                        if (_step > 0) setState(() => _step--);
                      },
                      controlsBuilder: (context, details) {
                        final last = _step == 2;
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              if (_step > 0)
                                TextButton(
                                  onPressed: details.onStepCancel,
                                  child: const Text('Back'),
                                ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: ShodashaTheme.teal,
                                    foregroundColor: ShodashaTheme.surface,
                                  ),
                                  onPressed: c.busy
                                      ? null
                                      : details.onStepContinue,
                                  child: c.busy && last
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          last
                                              ? addressStrings['save']!
                                              : 'Next',
                                        ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      steps: [
                        Step(
                          title: const Text('Name'),
                          isActive: _step >= 0,
                          state: _step > 0
                              ? StepState.complete
                              : StepState.indexed,
                          content: Column(
                            children: [
                              TextField(
                                controller: _label,
                                focusNode: _labelFocus,
                                style: const TextStyle(fontSize: 16),
                                keyboardType: TextInputType.name,
                                textInputAction: TextInputAction.next,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: addressStrings['labelField'],
                                  errorText: _touched && !_labelOk
                                      ? addressStrings['errLabel']
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 10),
                              SegmentedButton<AddrType>(
                                segments: [
                                  ButtonSegment(
                                    value: AddrType.home,
                                    label: Text(addressStrings['typeHome']!),
                                  ),
                                  ButtonSegment(
                                    value: AddrType.office,
                                    label: Text(addressStrings['typeOffice']!),
                                  ),
                                ],
                                selected: {_type},
                                onSelectionChanged: (s) =>
                                    setState(() => _type = s.first),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _phone,
                                style: const TextStyle(fontSize: 16),
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                maxLength: 15,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: addressStrings['phone'],
                                  counterText: '',
                                ),
                              ),
                            ],
                          ),
                        ),
                        Step(
                          title: const Text('Address'),
                          isActive: _step >= 1,
                          state: _step > 1
                              ? StepState.complete
                              : StepState.indexed,
                          content: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _locating
                                    ? null
                                    : _useCurrentLocation,
                                icon: _locating
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.my_location, size: 18),
                                label: const Text('Fill from current location'),
                              ),
                              if (_locateError != null)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 4,
                                    bottom: 4,
                                  ),
                                  child: Text(
                                    _locateError!,
                                    style: const TextStyle(
                                      color: ShodashaTheme.danger,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _pincode,
                                focusNode: _pincodeFocus,
                                style: const TextStyle(fontSize: 16),
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.next,
                                maxLength: 6,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: addressStrings['pincode'],
                                  counterText: '',
                                  errorText: _touched && !_pinOk
                                      ? addressStrings['errPincode']
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _line,
                                focusNode: _lineFocus,
                                style: const TextStyle(fontSize: 16),
                                minLines: 2,
                                maxLines: 3,
                                textInputAction: TextInputAction.next,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: addressStrings['addressLine'],
                                  errorText: _touched && !_lineOk
                                      ? addressStrings['errLine']
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _house,
                                      style: const TextStyle(fontSize: 16),
                                      textInputAction: TextInputAction.next,
                                      maxLength: 500,
                                      decoration: InputDecoration(
                                        labelText: addressStrings['house'],
                                        counterText: '',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextField(
                                      controller: _street,
                                      style: const TextStyle(fontSize: 16),
                                      textInputAction: TextInputAction.next,
                                      maxLength: 500,
                                      decoration: InputDecoration(
                                        labelText: addressStrings['street'],
                                        counterText: '',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _area,
                                style: const TextStyle(fontSize: 16),
                                textInputAction: TextInputAction.next,
                                maxLength: 500,
                                decoration: InputDecoration(
                                  labelText: addressStrings['area'],
                                  counterText: '',
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _landmark,
                                style: const TextStyle(fontSize: 16),
                                textInputAction: TextInputAction.done,
                                decoration: InputDecoration(
                                  labelText: addressStrings['landmark'],
                                ),
                              ),
                              if (_serviceNote != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.info_outline,
                                        size: 16,
                                        color: ShodashaTheme.blue,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _serviceNote!,
                                          style: const TextStyle(
                                            color: ShodashaTheme.blue,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Step(
                          title: const Text('Location'),
                          isActive: _step >= 2,
                          content: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(addressStrings['lift']!),
                                value: _lift,
                                onChanged: (v) => setState(() => _lift = v),
                              ),
                              const SizedBox(height: 6),
                              OutlinedButton.icon(
                                onPressed: _locating
                                    ? null
                                    : _useCurrentLocation,
                                icon: _locating
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.my_location),
                                label: const Text('Use current location'),
                              ),
                              if (_locateError != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    _locateError!,
                                    style: const TextStyle(
                                      color: ShodashaTheme.danger,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 6),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final pin = await pickMapPin(
                                    context,
                                    initial: _mapOk
                                        ? LatLng(_lat!, _lng!)
                                        : null,
                                  );
                                  if (pin != null) {
                                    setState(() {
                                      _lat = pin.latitude;
                                      _lng = pin.longitude;
                                    });
                                  }
                                },
                                icon: const Icon(Icons.map),
                                label: Text(
                                  _mapOk
                                      ? 'Pin placed — tap to change'
                                      : 'Place a pin on the map',
                                ),
                              ),
                              if (_touched && !_mapOk)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    addressStrings['errMap']!,
                                    style: const TextStyle(
                                      color: ShodashaTheme.danger,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              if (_saveError != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _saveError!,
                                    style: const TextStyle(
                                      color: ShodashaTheme.danger,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
