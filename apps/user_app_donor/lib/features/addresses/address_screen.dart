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
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui/app_button.dart';
import 'selected_address_store.dart';

part 'address_controller.dart';
part 'address_form_sheet.dart';

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
