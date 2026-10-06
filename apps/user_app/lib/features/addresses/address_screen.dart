// F5 — Addresses: list + add/edit form. Contract §4.3 + gates
// ignore_for_file: prefer_initializing_formals
// WHY: public ctor param `api:` is the API (same pattern as F2 auth);
// private initializing formals are unusable from other libraries.
// (pincode regex, (0,0) reject, office unlocks bulk rules, delete confirm,
// edit blocked when an undispatched order uses it — 409 message shown).
// States.md: skeleton → list → empty ("add your first address") → error.

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../core/location_service.dart';
import '../../core/theme.dart';
import 'map_picker.dart' show pickMapPin;
import 'selected_address_store.dart';

/// Hindi-first copy (TODO(F1): consolidate into lib/l10n/strings.dart).
const Map<String, String> addressStringsHi = {
  'title': 'Addresses',
  'addTitle': 'Naya address',
  'editTitle': 'Address badlein',
  'emptyTitle': 'Koi address nahi',
  'emptyHint': 'Pehla address add karein — delivery isi par hogi',
  'addFirst': 'Address add karein',
  'labelField': 'Naam (ghar/office)',
  'typeHome': 'Ghar',
  'typeOffice': 'Office',
  'phone': 'Phone',
  'pincode': 'Pincode',
  'addressLine': 'Pura pata',
  'landmark': 'Landmark (optional)',
  'lift': 'Lift hai',
  'save': 'Save karein',
  'saving': 'Save ho raha hai…',
  'delete': 'Delete karein',
  'deleteConfirmTitle': 'Address delete karein?',
  'deleteConfirmBody': 'Ye address hamesha ke liye hat jayega.',
  'deleteYes': 'Haan, delete karein',
  'deleteNo': 'Rehne dein',
  'defaultTick': 'Default',
  'errPincode': '6-digit pincode likhein',
  'errLine': 'Pura pata likhein',
  'errLabel': 'Naam likhein',
  'errOfficeBulk': 'Office address par bulk rules lagenge (monthly bill)',
  'editBlockedTitle': 'Abhi edit nahi ho sakta',
  'editBlockedBody':
      'Is address par undispatched order hai — pehle use '
      'deliver hone dein ya WhatsApp par baat karein',
  'loadFailed': 'Address load nahi hue',
  'offline': 'Internet nahi — dobara try karein',
  'saved': 'Address save ho gaya',
  'deleted': 'Address delete ho gaya',
  'retry': 'Dobara try karein',
};

/// Pincode: exactly 6 digits, first non-zero (Indian postal norms).
bool isValidPincode(String v) => RegExp(r'^[1-9][0-9]{5}$').hasMatch(v);

enum AddrType { home, office }

/// F7: two-line bar detail — house/street/area when present, else the
/// saved address line. One helper, both bars (home + sheet) stay honest.
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

  /// 011_port full format (nullable, back-compat).
  final String? house;
  final String? street;
  final String? area;

  /// Map pin (backend rejects 0,0 — form gates on a real pin).
  final double lat;
  final double lng;

  /// Wire payload. Contract §4.3 uses `formatted` for the address text —
  /// `address_line`/`phone` are app-model conveniences the server ignores,
  /// so the typed line MUST ride on `formatted` or saved addresses come
  /// back with empty text (the "can't change address" bug).
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

  AddrStatus get status => _status;
  List<AddressEntry> get items => List.unmodifiable(_items);
  String? get errorMessage => _errorMessage;
  bool get busy => _busy;

  /// Live delivery selection (011_port): Home / checkout / Addresses agree.
  /// In-memory; main.dart binds a [SelectedAddressStore] for persistence.
  String? _selectedId;
  SelectedAddressStore? _store;

  String? get selectedId => _selectedId;

  /// Binds persistence (call once after store.load in main).
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
    _store?.select(_selectedId); // ignore: discarded_futures
    _notify();
  }

  /// Resolves the delivery address: selected (when still saved) → default →
  /// first → null. Callers (home bar, checkout) use this, never [items].
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
    try {
      final raw = await _api.listAddresses();
      _items = raw
          .whereType<Map<String, dynamic>>()
          .map(AddressEntry.fromApi)
          .toList();
      _status = AddrStatus.loaded;
      // Adopt a persisted selection that arrived before the items did:
      // bindSelection runs before first load, so without this the choice
      // is forgotten on every restart (resolve falls back to first).
      if (_selectedId == null) {
        final persisted = _store?.selectedId;
        if (persisted != null && _items.any((a) => a.id == persisted)) {
          _selectedId = persisted;
        }
      }
    } on ApiException catch (e) {
      _status = AddrStatus.error;
      _errorMessage = e.isNetwork
          ? addressStringsHi['offline']
          : addressStringsHi['loadFailed'];
    } catch (_) {
      _status = AddrStatus.error;
      _errorMessage = addressStringsHi['loadFailed'];
    }
    _notify();
  }

  Future<bool> save(AddressEntry entry, {bool isNew = true}) async {
    _busy = true;
    _saveErrorClear();
    _notify();
    try {
      final body = entry.toApi();
      final saved = isNew
          ? AddressEntry.fromApi(await _api.createAddress(body))
          : AddressEntry.fromApi(await _api.patchAddress(entry.id, body));
      final idx = _items.indexWhere((a) => a.id == saved.id);
      if (idx >= 0) {
        _items[idx] = saved;
      } else {
        _items.add(saved);
      }
      select(saved.id); // newly saved address becomes the delivery address
      return true;
    } on ApiException catch (e) {
      // S3: surfaced inline by the form sheet (stays open + retry).
      _errorMessage = e.isNetwork
          ? addressStringsHi['offline']
          : addressStringsHi['loadFailed'];
      return false;
    } catch (_) {
      _errorMessage = addressStringsHi['loadFailed'];
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _saveErrorClear() {
    _errorMessage = null;
  }

  Future<bool> delete(String id) async {
    _busy = true;
    _notify();
    try {
      await _api.deleteAddress(id);
      _items.removeWhere((a) => a.id == id);
      if (_selectedId == id) select(null);
      return true;
    } on ApiException catch (e) {
      // Contract: DELETE blocked by active orders/subs → 409 message shown.
      _errorMessage = e.statusCode == 409
          ? addressStringsHi['editBlockedBody']
          : addressStringsHi['offline'];
      return false;
    } catch (_) {
      _errorMessage = addressStringsHi['offline'];
      return false;
    } finally {
      _busy = false;
      _notify();
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

/// Addresses tab-page (list + add/edit dialog form + gates).
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (_) =>
          _AddressFormSheet(controller: widget.controller, existing: existing),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(addressStringsHi['saved']!)));
    }
  }

  Future<void> _confirmDelete(AddressEntry a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: ShodashaTheme.shape,
        title: Text(addressStringsHi['deleteConfirmTitle']!),
        content: Text(addressStringsHi['deleteConfirmBody']!),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(addressStringsHi['deleteNo']!),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(addressStringsHi['deleteYes']!),
          ),
        ],
      ),
    );
    if (ok == true) {
      final done = await widget.controller.delete(a.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              done
                  ? addressStringsHi['deleted']!
                  : (widget.controller.errorMessage ??
                        addressStringsHi['offline']!),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(title: Text(addressStringsHi['title']!)),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          if (c.status == AddrStatus.loading && c.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (c.status == AddrStatus.error && c.items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c.errorMessage ?? ''),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: c.load,
                    child: Text(addressStringsHi['retry']!),
                  ),
                ],
              ),
            );
          }
          if (c.items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    addressStringsHi['emptyTitle']!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    addressStringsHi['emptyHint']!,
                    style: const TextStyle(
                      color: ShodashaTheme.muted,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _openForm(),
                    child: Text(addressStringsHi['addFirst']!),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: c.load,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: c.items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                if (i == c.items.length) {
                  return ElevatedButton(
                    onPressed: () => _openForm(),
                    child: Text(addressStringsHi['addFirst']!),
                  );
                }
                final a = c.items[i];
                final selected =
                    c.selectedId == a.id ||
                    (c.selectedId == null && c.resolve()?.id == a.id);
                return InkWell(
                  onTap: () => c.select(a.id),
                  borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: selected
                            ? ShodashaTheme.blue
                            : ShodashaTheme.border,
                        width: selected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            RadioGroup<String>(
                              groupValue: c.resolve()?.id,
                              onChanged: (v) => c.select(v),
                              child: Radio<String>(value: a.id),
                            ),
                            Expanded(
                              child: Text(
                                a.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: ShodashaTheme.ink,
                                ),
                              ),
                            ),
                            if (a.isDefault)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: ShodashaTheme.blueTint,
                                  borderRadius: BorderRadius.circular(
                                    ShodashaTheme.radius,
                                  ),
                                ),
                                child: Text(
                                  addressStringsHi['defaultTick']!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: ShodashaTheme.blue,
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
                              child: const Text('Badlein'),
                            ),
                            TextButton(
                              onPressed: () => _confirmDelete(a),
                              child: Text(
                                addressStringsHi['delete']!,
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

/// Add/edit form sheet (label, type, phone, pincode, line, landmark, lift).
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
  String? _locateError;

  /// a11y-6: focus lands on the first invalid field at submit.
  final _labelFocus = FocusNode();
  final _pincodeFocus = FocusNode();
  final _lineFocus = FocusNode();

  /// Stepper state (Wave 1 polish): 0 Naam → 1 Pata → 2 Location.
  int _step = 0;

  /// S3: save failure stays in-sheet with inline error + retry (no silent pop).
  String? _saveError;

  /// Map pin (null = not pinned yet; backend rejects 0,0).
  double? _lat;
  double? _lng;

  bool get _isNew => widget.existing == null;

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
    _labelFocus.dispose();
    _pincodeFocus.dispose();
    _lineFocus.dispose();
    _line.dispose();
    _landmark.dispose();
    _house.dispose();
    _street.dispose();
    _area.dispose();
    super.dispose();
  }

  bool get _pinOk => isValidPincode(_pincode.text);
  bool get _labelOk => _label.text.trim().isNotEmpty;
  bool get _lineOk => _line.text.trim().length >= 6;
  bool get _mapOk => _lat != null && _lng != null;
  bool get _valid => _pinOk && _labelOk && _lineOk && _mapOk;

  Future<void> _save() async {
    setState(() {
      _touched = true;
      _saveError = null;
    });
    // a11y-6: focus lands on the first invalid field (map-pin misses
    // keep the inline map prompt — no field to focus).
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
      Navigator.of(context).pop(true);
    } else {
      // S3: stay open — inline error + retry instead of a silent dismiss.
      setState(
        () => _saveError =
            widget.controller.errorMessage ?? addressStringsHi['offline'],
      );
    }
  }

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
      if (_stepOk(_step)) setState(() => _step++);
      return;
    }
    await _save();
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
        if (_street.text.trim().isEmpty && loc.street != null) {
          _street.text = loc.street!;
        }
        if (_area.text.trim().isEmpty && loc.area != null) {
          _area.text = loc.area!;
        }
        if (_line.text.trim().isEmpty) _line.text = loc.displayLabel;
        if (_pincode.text.trim().isEmpty && loc.postalCode != null) {
          _pincode.text = loc.postalCode!;
        }
      });
    } on LocationError catch (e) {
      if (!mounted) return;
      setState(() => _locateError = e.userMessage);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    // Fixed sheet height: the vertical Stepper needs a bounded viewport
    // (it scrolls internally per step instead of one 800px column).
    final sheetHeight = MediaQuery.of(context).size.height * 0.88;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: sheetHeight,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isNew
                    ? addressStringsHi['addTitle']!
                    : addressStringsHi['editTitle']!,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              if (_type == AddrType.office) ...[
                const SizedBox(height: 6),
                Text(
                  addressStringsHi['errOfficeBulk']!,
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
                                child: const Text('Peeche'),
                              ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed:
                                    (c.busy ||
                                        (!_stepOk(_step) &&
                                            _step < 2 &&
                                            _touched) ||
                                        (last && !_valid))
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
                                            ? addressStringsHi['save']!
                                            : 'Aage',
                                      ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    steps: [
                      Step(
                        title: const Text('Naam'),
                        isActive: _step >= 0,
                        state: _step > 0
                            ? StepState.complete
                            : StepState.indexed,
                        content: Column(
                          children: [
                            TextField(
                              controller: _label,
                              focusNode: _labelFocus,
                              // WHY: 16px stops iOS auto-zoom (mobile-native A4).
                              style: const TextStyle(fontSize: 16),
                              keyboardType: TextInputType.name,
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: addressStringsHi['labelField'],
                                errorText: _touched && !_labelOk
                                    ? addressStringsHi['errLabel']
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 10),
                            SegmentedButton<AddrType>(
                              segments: [
                                ButtonSegment(
                                  value: AddrType.home,
                                  label: Text(addressStringsHi['typeHome']!),
                                ),
                                ButtonSegment(
                                  value: AddrType.office,
                                  label: Text(addressStringsHi['typeOffice']!),
                                ),
                              ],
                              selected: {_type},
                              onSelectionChanged: (s) =>
                                  setState(() => _type = s.first),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _phone,
                              // WHY: 16px stops iOS auto-zoom (mobile-native A4).
                              style: const TextStyle(fontSize: 16),
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              maxLength: 15,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: addressStringsHi['phone'],
                                counterText: '',
                              ),
                            ),
                          ],
                        ),
                      ),
                      Step(
                        title: const Text('Pata'),
                        isActive: _step >= 1,
                        state: _step > 1
                            ? StepState.complete
                            : StepState.indexed,
                        content: Column(
                          children: [
                            TextField(
                              controller: _pincode,
                              focusNode: _pincodeFocus,
                              // WHY: 16px stops iOS auto-zoom (mobile-native A4).
                              style: const TextStyle(fontSize: 16),
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              maxLength: 6,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: addressStringsHi['pincode'],
                                counterText: '',
                                errorText: _touched && !_pinOk
                                    ? addressStringsHi['errPincode']
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _line,
                              focusNode: _lineFocus,
                              // WHY: 16px stops iOS auto-zoom (mobile-native A4).
                              style: const TextStyle(fontSize: 16),
                              minLines: 2,
                              maxLines: 3,
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: addressStringsHi['addressLine'],
                                errorText: _touched && !_lineOk
                                    ? addressStringsHi['errLine']
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _house,
                                    // WHY: 16px stops iOS auto-zoom (mobile-native A4).
                                    style: const TextStyle(fontSize: 16),
                                    textInputAction: TextInputAction.next,
                                    maxLength: 500,
                                    decoration: const InputDecoration(
                                      labelText: 'Makan / House no.',
                                      counterText: '',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _street,
                                    // WHY: 16px stops iOS auto-zoom (mobile-native A4).
                                    style: const TextStyle(fontSize: 16),
                                    textInputAction: TextInputAction.next,
                                    maxLength: 500,
                                    decoration: const InputDecoration(
                                      labelText: 'Gali / Street',
                                      counterText: '',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _area,
                              // WHY: 16px stops iOS auto-zoom (mobile-native A4).
                              style: const TextStyle(fontSize: 16),
                              textInputAction: TextInputAction.next,
                              maxLength: 500,
                              decoration: const InputDecoration(
                                labelText: 'Area / Mohalla',
                                counterText: '',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _landmark,
                              // WHY: 16px stops iOS auto-zoom (mobile-native A4).
                              style: const TextStyle(fontSize: 16),
                              textInputAction: TextInputAction.done,
                              decoration: InputDecoration(
                                labelText: addressStringsHi['landmark'],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Step(
                        title: const Text('Sthan'),
                        isActive: _step >= 2,
                        content: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(addressStringsHi['lift']!),
                              value: _lift,
                              onChanged: (v) => setState(() => _lift = v),
                            ),
                            const SizedBox(height: 6),
                            OutlinedButton.icon(
                              onPressed: _locating ? null : _useCurrentLocation,
                              icon: _locating
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.my_location),
                              label: const Text('Current location use karein'),
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
                                  initial: _mapOk ? LatLng(_lat!, _lng!) : null,
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
                                    ? 'Pin laga hai — badalne ke liye tap karein'
                                    : 'Map par pin lagayein',
                              ),
                            ),
                            if (_touched && !_mapOk)
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text(
                                  'Map par pin lagana zaroori hai',
                                  style: TextStyle(
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
    );
  }
}
