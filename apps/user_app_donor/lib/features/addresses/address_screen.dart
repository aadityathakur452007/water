// Addresses: list + tag-first add/edit form, serviceability check, selection store.
//
// Contract §4.3: GET/POST/PATCH/DELETE /addresses. `formatted` carries the
// typed address line; house/street/area/phone ride as their own fields.
// 409 means an undispatched order holds the address — the message is shown,
// never swallowed.
//
// Maximum 3 saved delivery addresses per customer (Home, Work, Other).
// Human-first Indian address flow: flat/house, street/locality, pincode, landmark,
// and lift-logistics (critical for 20L jars) without confusing raw GPS/map steps.
//
// ignore_for_file: prefer_initializing_formals
// WHY: the public `api:` parameter must stay public while the field is
// private; a private initializing formal is unusable from other libraries.

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui/app_button.dart';
import 'selected_address_store.dart';

/// English copy for the v1 app (ADR-120, ADR-186).
const Map<String, String> addressStrings = {
  'title': 'Delivery addresses',
  'addTitle': 'Add delivery address',
  'editTitle': 'Edit delivery address',
  'emptyTitle': 'No addresses saved',
  'emptyHint': 'Add your delivery location — pure 20L water will reach your doorstep.',
  'addFirst': 'Add delivery address',
  'labelField': 'Address label (e.g. Home, Work)',
  'typeHome': 'Home',
  'typeOffice': 'Work',
  'typeOther': 'Other',
  'phone': 'Contact phone (10 digits)',
  'receiverName': 'Receiver name',
  'pincode': 'Pincode (6 digits)',
  'addressLine': 'Apartment / Street / Locality',
  'house': 'Flat / House / Floor no.',
  'street': 'Street / Society / Colony',
  'area': 'Locality / Area',
  'landmark': 'Landmark (optional)',
  'lift': 'Lift available in building',
  'liftHelper': 'Helps delivery partners carry heavy 20L jars smoothly',
  'save': 'Save delivery address',
  'update': 'Update address',
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
  'errPincode': 'Enter a valid 6-digit Indian pincode',
  'errLine': 'Enter apartment, street or locality',
  'errHouse': 'Enter house or flat number',
  'errLabel': 'Enter an address label',
  'errPhone': 'Enter a valid 10-digit mobile number, or leave it blank.',
  'errOfficeBulk': 'Office addresses use bulk rules (monthly bill).',
  'editBlockedTitle': "Can't edit right now",
  'editBlockedBody':
      'An undispatched order uses this address. Let it '
      'deliver first, or contact support.',
  'loadFailed': 'Could not load addresses.',
  'offline': 'No internet — check your connection and retry.',
  'server': 'Server problem — retry in a moment.',
  'saved': 'Address saved successfully',
  'deleted': 'Address deleted',
  'retry': 'Retry',
  'savedHeader': 'SAVED DELIVERY ADDRESSES',
  'savedCount': 'of 3 saved',
  'maxReached':
      'You can save up to 3 delivery addresses (Home, Work, Other). Edit or delete an address to change.',
  'serviceNo': "We don't deliver to this pincode yet. You can still save it.",
  'serviceYes': "✓ Delivery available at this pincode.",
  'serviceChecking': "Checking delivery availability…",
  'serviceUnknown':
      "Couldn't verify delivery to this pincode online. You can still save it.",
  'discardTitle': 'Discard changes?',
  'discardBody': 'Your changes to this address will be lost.',
  'discardKeep': 'Keep editing',
  'discardConfirm': 'Discard',
};

/// Pincode: exactly 6 digits, first non-zero (Indian postal norms).
bool isValidPincode(String v) => RegExp(r'^[1-9][0-9]{5}$').hasMatch(v.trim());

/// Optional address phone: blank is allowed; otherwise accept the same
/// `+91`/`91`/`0`/space variants as customer auth and require a valid mobile.
bool isValidOptionalPhone(String raw) {
  if (raw.trim().isEmpty) return true;
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('91') && digits.length == 12) {
    digits = digits.substring(2);
  } else if (digits.startsWith('0') && digits.length == 11) {
    digits = digits.substring(1);
  }
  return RegExp(r'^[6-9]\d{9}$').hasMatch(digits);
}

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

  void _notifyMaxReached() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(addressStrings['maxReached']!),
      ),
    );
  }

  Future<void> _openForm({AddressEntry? existing}) async {
    if (existing == null && widget.controller.items.length >= 3) {
      _notifyMaxReached();
      return;
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ShodashaTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ShodashaTheme.radiusSheet),
        ),
      ),
      builder: (_) => _AddressFormSheet(
        controller: widget.controller,
        existing: existing,
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(addressStrings['saved']!)),
      );
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
            style: TextButton.styleFrom(foregroundColor: ShodashaTheme.muted),
            child: Text(addressStrings['deleteNo']!),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: ShodashaTheme.danger,
              foregroundColor: Colors.white,
            ),
            child: Text(addressStrings['deleteYes']!),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final success = await widget.controller.delete(a.id);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(addressStrings['deleted']!)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.controller.errorMessage ?? addressStrings['server']!,
            ),
          ),
        );
      }
    }
  }

  IconData _iconForTag(String label, AddrType type) {
    final l = label.toLowerCase();
    if (l.contains('home') || type == AddrType.home) {
      return Icons.home_rounded;
    }
    if (l.contains('work') || l.contains('office') || type == AddrType.office) {
      return Icons.apartment_rounded;
    }
    return Icons.place_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          addressStrings['title']!,
          style: const TextStyle(
            color: ShodashaTheme.ink,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        elevation: 0,
        backgroundColor: ShodashaTheme.surface,
        iconTheme: const IconThemeData(color: ShodashaTheme.ink),
      ),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          if (c.status == AddrStatus.loading && c.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (c.status == AddrStatus.error && c.items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 36,
                      color: ShodashaTheme.danger,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      c.errorMessage ?? addressStrings['loadFailed']!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: AppSpacing.md),
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
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: ShodashaTheme.tealTint,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        size: 40,
                        color: ShodashaTheme.teal,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      addressStrings['emptyTitle']!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: ShodashaTheme.ink,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      addressStrings['emptyHint']!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: ShodashaTheme.muted,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppButton(
                      label: addressStrings['addFirst']!,
                      kind: AppButtonKind.primary,
                      icon: Icons.add_rounded,
                      onPressed: () => _openForm(),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: c.load,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              itemCount: c.items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
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
                final a = c.items[i - 1];
                final selected = c.selectedId == a.id ||
                    (c.selectedId == null && c.resolve()?.id == a.id);
                return InkWell(
                  onTap: () => c.select(a.id),
                  borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: selected
                          ? ShodashaTheme.tealTint.withValues(alpha: 0.35)
                          : ShodashaTheme.surface,
                      border: Border.all(
                        color: selected
                            ? ShodashaTheme.teal
                            : ShodashaTheme.border,
                        width: selected ? 1.5 : 1,
                      ),
                      borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                      boxShadow: ShodashaTheme.subtleCardShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: selected
                                    ? ShodashaTheme.teal.withValues(alpha: 0.12)
                                    : ShodashaTheme.tealTint,
                                borderRadius: BorderRadius.circular(
                                    ShodashaTheme.radiusSm),
                              ),
                              child: Icon(
                                _iconForTag(a.label, a.type),
                                size: 18,
                                color: ShodashaTheme.teal,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                a.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: ShodashaTheme.ink,
                                ),
                              ),
                            ),
                            if (selected)
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 20,
                                color: ShodashaTheme.teal,
                              ),
                            if (a.isDefault)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: ShodashaTheme.tealTint,
                                  borderRadius: BorderRadius.circular(
                                    ShodashaTheme.radiusSm,
                                  ),
                                ),
                                child: Text(
                                  addressStrings['defaultTick']!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: ShodashaTheme.teal,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          addressDetailLine(a),
                          style: const TextStyle(
                            color: ShodashaTheme.ink,
                            fontSize: 14,
                            height: 1.3,
                          ),
                        ),
                        Text(
                          'Pincode: ${a.pincode}',
                          style: const TextStyle(
                            color: ShodashaTheme.muted,
                            fontSize: 12,
                          ),
                        ),
                        if (a.landmark != null && a.landmark!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.near_me_outlined,
                                  size: 13,
                                  color: ShodashaTheme.muted,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Landmark: ${a.landmark!}',
                                    style: const TextStyle(
                                      color: ShodashaTheme.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (a.lift)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.elevator_outlined,
                                  size: 14,
                                  color: ShodashaTheme.teal,
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'Lift available in building',
                                  style: TextStyle(
                                    color: ShodashaTheme.teal,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: () => _openForm(existing: a),
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: const Text('Edit'),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: ShodashaTheme.ink,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            TextButton.icon(
                              onPressed: () => _confirmDelete(a),
                              icon: const Icon(Icons.delete_outline_rounded,
                                  size: 16),
                              label: Text(addressStrings['delete']!),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: ShodashaTheme.danger,
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
      bottomNavigationBar: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          if (c.items.isEmpty) return const SizedBox.shrink();
          final canAdd = c.items.length < 3;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: canAdd
                  ? AppButton(
                      label: addressStrings['addFirst']!,
                      kind: AppButtonKind.primary,
                      icon: Icons.add_rounded,
                      onPressed: () => _openForm(),
                    )
                  : AppButton(
                      label: 'All 3 address slots used (Home, Work, Other)',
                      kind: AppButtonKind.secondary,
                      onPressed: _notifyMaxReached,
                    ),
            ),
          );
        },
      ),
    );
  }
}

/// Redesigned tag-first Indian address form bottom sheet (ADR-186).
/// Completely removes clunky Stepper and manual GPS/map steps.
class _AddressFormSheet extends StatefulWidget {
  const _AddressFormSheet({required this.controller, this.existing});

  final AddressController controller;
  final AddressEntry? existing;

  @override
  State<_AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends State<_AddressFormSheet> {
  late final TextEditingController _house;
  late final TextEditingController _street;
  late final TextEditingController _pincode;
  late final TextEditingController _landmark;
  late final TextEditingController _customLabel;
  late final TextEditingController _phone;

  String _selectedTag = 'Home'; // 'Home', 'Work', 'Other'
  bool _lift = false;
  bool _touched = false;
  bool _busy = false;
  String? _saveError;
  _ServiceCheck _serviceState = _ServiceCheck.unchecked;

  final _houseFocus = FocusNode();
  final _streetFocus = FocusNode();
  final _pincodeFocus = FocusNode();

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _house = TextEditingController(text: e?.house ?? '');
    _street = TextEditingController(text: e?.street ?? e?.area ?? '');
    _pincode = TextEditingController(text: e?.pincode ?? '');
    _landmark = TextEditingController(text: e?.landmark ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _lift = e?.lift ?? false;

    if (e != null) {
      final lbl = e.label.trim();
      if (lbl == 'Home') {
        _selectedTag = 'Home';
        _customLabel = TextEditingController();
      } else if (lbl == 'Work' || e.type == AddrType.office) {
        _selectedTag = 'Work';
        _customLabel = TextEditingController();
      } else {
        _selectedTag = 'Other';
        _customLabel = TextEditingController(text: lbl);
      }
      _serviceState = _ServiceCheck.unknown;
    } else {
      // Pick next available tag slot
      final existingLabels =
          widget.controller.items.map((i) => i.label).toSet();
      if (!existingLabels.contains('Home')) {
        _selectedTag = 'Home';
      } else if (!existingLabels.contains('Work')) {
        _selectedTag = 'Work';
      } else {
        _selectedTag = 'Other';
      }
      _customLabel = TextEditingController();
    }
  }

  @override
  void dispose() {
    _house.dispose();
    _street.dispose();
    _pincode.dispose();
    _landmark.dispose();
    _customLabel.dispose();
    _phone.dispose();
    _houseFocus.dispose();
    _streetFocus.dispose();
    _pincodeFocus.dispose();
    super.dispose();
  }

  bool get _houseOk => _house.text.trim().isNotEmpty;
  bool get _streetOk => _street.text.trim().isNotEmpty;
  bool get _pinOk => isValidPincode(_pincode.text);
  bool get _phoneOk => isValidOptionalPhone(_phone.text);
  bool get _valid => _houseOk && _streetOk && _pinOk && _phoneOk;

  Future<void> _checkPincodeService(String pin) async {
    final clean = pin.trim();
    if (!isValidPincode(clean)) {
      if (_serviceState != _ServiceCheck.unchecked) {
        setState(() => _serviceState = _ServiceCheck.unchecked);
      }
      return;
    }
    setState(() => _serviceState = _ServiceCheck.checking);
    final serviceable = await widget.controller.checkServiceable(clean);
    if (!mounted) return;
    setState(() {
      _serviceState = serviceable == false
          ? _ServiceCheck.notServiceable
          : serviceable == true
              ? _ServiceCheck.serviceable
              : _ServiceCheck.unknown;
    });
  }

  Future<void> _save() async {
    setState(() {
      _touched = true;
      _saveError = null;
    });

    if (!_houseOk) {
      _houseFocus.requestFocus();
      return;
    }
    if (!_streetOk) {
      _streetFocus.requestFocus();
      return;
    }
    if (!_pinOk) {
      _pincodeFocus.requestFocus();
      return;
    }
    if (!_valid) return;

    setState(() => _busy = true);
    FocusScope.of(context).unfocus();

    final house = _house.text.trim();
    final street = _street.text.trim();
    final fullAddress = '$house, $street';
    final landmark = _landmark.text.trim().isEmpty ? null : _landmark.text.trim();
    final pincode = _pincode.text.trim();
    final phone = _phone.text.trim();

    String label = _selectedTag;
    if (_selectedTag == 'Other' && _customLabel.text.trim().isNotEmpty) {
      label = _customLabel.text.trim();
    }

    final entry = AddressEntry(
      id: widget.existing?.id ?? '',
      label: label,
      type: _selectedTag == 'Work' ? AddrType.office : AddrType.home,
      phone: phone,
      pincode: pincode,
      addressLine: fullAddress,
      house: house,
      street: street,
      area: street,
      landmark: landmark,
      lift: _lift,
      isDefault: widget.existing?.isDefault ?? false,
      lat: widget.existing?.lat ?? 23.2599,
      lng: widget.existing?.lng ?? 77.4126,
    );

    final ok = await widget.controller.save(entry, isNew: _isNew);
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saveError =
            widget.controller.errorMessage ?? addressStrings['server']!;
      });
    }
  }

  Widget _buildTagButton(String tag, IconData icon) {
    final selected = _selectedTag == tag;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedTag = tag);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? ShodashaTheme.tealTint
                : ShodashaTheme.surface,
            border: Border.all(
              color: selected
                  ? ShodashaTheme.teal
                  : ShodashaTheme.border,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected
                    ? ShodashaTheme.teal
                    : ShodashaTheme.muted,
              ),
              const SizedBox(width: 6),
              Text(
                tag,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected
                      ? ShodashaTheme.teal
                      : ShodashaTheme.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sheet Drag Handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: ShodashaTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isNew
                            ? addressStrings['addTitle']!
                            : addressStrings['editTitle']!,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: ShodashaTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Deliveries in India · Max 3 saved addresses',
                        style: TextStyle(
                          fontSize: 12,
                          color: ShodashaTheme.muted,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22),
                    color: ShodashaTheme.muted,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Deliver To Tag Selector
              const Text(
                'DELIVER TO',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: ShodashaTheme.muted,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  _buildTagButton('Home', Icons.home_rounded),
                  const SizedBox(width: AppSpacing.sm),
                  _buildTagButton('Work', Icons.apartment_rounded),
                  const SizedBox(width: AppSpacing.sm),
                  _buildTagButton('Other', Icons.place_rounded),
                ],
              ),

              if (_selectedTag == 'Other') ...[
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _customLabel,
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    labelText: 'Custom Label (e.g. Parents, Gym)',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(ShodashaTheme.radiusSm),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.md),

              // House / Flat No.
              TextField(
                controller: _house,
                focusNode: _houseFocus,
                textInputAction: TextInputAction.next,
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  labelText: addressStrings['house'],
                  hintText: 'e.g. Flat 402, 4th Floor / House 12',
                  prefixIcon: const Icon(Icons.door_front_door_outlined, size: 20),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                  ),
                  errorText: _touched && !_houseOk
                      ? addressStrings['errHouse']
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Apartment / Street / Locality
              TextField(
                controller: _street,
                focusNode: _streetFocus,
                textInputAction: TextInputAction.next,
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  labelText: addressStrings['addressLine'],
                  hintText: 'e.g. Royal Palms, Arera Colony',
                  prefixIcon: const Icon(Icons.location_city_outlined, size: 20),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                  ),
                  errorText: _touched && !_streetOk
                      ? addressStrings['errLine']
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Pincode & Landmark Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: TextField(
                      controller: _pincode,
                      focusNode: _pincodeFocus,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      maxLength: 6,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        labelText: addressStrings['pincode'],
                        hintText: 'e.g. 462016',
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(ShodashaTheme.radiusSm),
                        ),
                        errorText: _touched && !_pinOk
                            ? addressStrings['errPincode']
                            : null,
                      ),
                      onChanged: (val) {
                        setState(() {});
                        _checkPincodeService(val);
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 6,
                    child: TextField(
                      controller: _landmark,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        labelText: addressStrings['landmark'],
                        hintText: 'e.g. Opp. Apollo Pharmacy',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(ShodashaTheme.radiusSm),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Serviceability feedback
              if (_serviceState == _ServiceCheck.checking)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        addressStrings['serviceChecking']!,
                        style: const TextStyle(
                            fontSize: 12, color: ShodashaTheme.muted),
                      ),
                    ],
                  ),
                ),
              if (_serviceState == _ServiceCheck.serviceable)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    addressStrings['serviceYes']!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ShodashaTheme.teal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (_serviceState == _ServiceCheck.notServiceable)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    addressStrings['serviceNo']!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ShodashaTheme.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

              const SizedBox(height: AppSpacing.sm),

              // Water Logistics: Lift Available Container
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: 8),
                decoration: BoxDecoration(
                  color: ShodashaTheme.surface,
                  border: Border.all(color: ShodashaTheme.border),
                  borderRadius:
                      BorderRadius.circular(ShodashaTheme.radiusSm),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: ShodashaTheme.tealTint,
                        borderRadius:
                            BorderRadius.circular(ShodashaTheme.radiusSm),
                      ),
                      child: const Icon(
                        Icons.elevator_outlined,
                        size: 20,
                        color: ShodashaTheme.teal,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            addressStrings['lift']!,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: ShodashaTheme.ink,
                            ),
                          ),
                          Text(
                            addressStrings['liftHelper']!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: ShodashaTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _lift,
                      activeTrackColor: ShodashaTheme.teal,
                      onChanged: (v) => setState(() => _lift = v),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.sm),

              // Contact Phone
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  labelText: addressStrings['phone'],
                  hintText: 'Optional contact number for delivery rider',
                  prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                  ),
                  errorText: _touched && !_phoneOk
                      ? addressStrings['errPhone']
                      : null,
                ),
                onChanged: (_) => setState(() {}),
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

              const SizedBox(height: AppSpacing.lg),

              // Save CTA
              AppButton(
                label: _isNew
                    ? addressStrings['save']!
                    : addressStrings['update']!,
                kind: AppButtonKind.primary,
                height: 48,
                busy: _busy,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
