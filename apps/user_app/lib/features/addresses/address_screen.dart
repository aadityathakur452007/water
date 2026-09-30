// F5 — Addresses: list + add/edit form. Contract §4.3 + gates
// ignore_for_file: prefer_initializing_formals
// WHY: public ctor param `api:` is the API (same pattern as F2 auth);
// private initializing formals are unusable from other libraries.
// (pincode regex, (0,0) reject, office unlocks bulk rules, delete confirm,
// edit blocked when an undispatched order uses it — 409 message shown).
// States.md: skeleton → list → empty ("add your first address") → error.

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

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
  'editBlockedBody': 'Is address par undispatched order hai — pehle use '
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

  Map<String, dynamic> toApi() => {
        'label': label,
        'type': type == AddrType.home ? 'home' : 'office',
        'phone': phone,
        'pincode': pincode,
        'address_line': addressLine,
        'landmark': landmark,
        'lift_flag': lift,
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
      return true;
    } on ApiException {
      return false;
    } catch (_) {
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<bool> delete(String id) async {
    _busy = true;
    _notify();
    try {
      await _api.deleteAddress(id);
      _items.removeWhere((a) => a.id == id);
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
      builder: (_) => _AddressFormSheet(
        controller: widget.controller,
        existing: existing,
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(addressStringsHi['saved']!)),
      );
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
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: ShodashaTheme.border),
                    borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
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
                                borderRadius:
                                    BorderRadius.circular(ShodashaTheme.radius),
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
                            child: const Text('Edit'),
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
  late AddrType _type;
  bool _lift = false;
  bool _touched = false;

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
    _type = e?.type ?? AddrType.home;
    _lift = e?.lift ?? false;
  }

  @override
  void dispose() {
    _label.dispose();
    _phone.dispose();
    _pincode.dispose();
    _line.dispose();
    _landmark.dispose();
    super.dispose();
  }

  bool get _pinOk => isValidPincode(_pincode.text);
  bool get _labelOk => _label.text.trim().isNotEmpty;
  bool get _lineOk => _line.text.trim().length >= 6;
  bool get _valid => _pinOk && _labelOk && _lineOk;

  Future<void> _save() async {
    setState(() => _touched = true);
    if (!_valid) return;
    FocusScope.of(context).unfocus();
    final saved = await widget.controller.save(
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
      ),
      isNew: _isNew,
    );
    if (!mounted) return;
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
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
                const SizedBox(height: 14),
                TextField(
                  controller: _label,
                  keyboardType: TextInputType.name,
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
                  controller: _pincode,
                  keyboardType: TextInputType.number,
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
                  minLines: 2,
                  maxLines: 3,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: addressStringsHi['addressLine'],
                    errorText: _touched && !_lineOk
                        ? addressStringsHi['errLine']
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _landmark,
                  decoration: InputDecoration(
                    labelText: addressStringsHi['landmark'],
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(addressStringsHi['lift']!),
                  value: _lift,
                  onChanged: (v) => setState(() => _lift = v),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (c.busy || !_valid) ? null : _save,
                    child: c.busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(addressStringsHi['save']!),
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
