// S6 — Plan builder: server estimate → create (one idempotent submit).
//
// Ported from the legacy monthly calculator + activation (031: "Ye
// Subscription Shuru Karein") without its client money math: the amount shown
// is `POST /subscriptions/estimate` (water + once-only deposit). The legacy
// upfront ₹30/jar + ₹150 deposit labels are deliberately not ported — money
// may only come from a server response (spec §2 money door).
//
// Create payload mirrors the legacy checkout: `sku_mix` is the dominant SKU
// (the calculator builds refill plans), `window` stays empty because the
// server scheduler owns the delivery window (`SUB_WINDOW_START`) — inventing a
// client slot would be a fake promise. The payment/billing mode fields are not
// sent because the ported ApiClient.createSubscription contract does not carry
// them (server default: per-delivery COD).
//
// States.md: addresses/estimate loading (skeleton/bar) → error + retry; submit
// pending → server error copy or success pop; no amount is ever computed here.

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import 'subscription_controller.dart';

/// Opens the plan builder; resolves with the server create response (or null).
Future<Map<String, dynamic>?> showPlanBuilderSheet(
  BuildContext context, {
  required ApiClient api,
}) => showModalBottomSheet<Map<String, dynamic>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(ShodashaTheme.radiusSheet),
    ),
  ),
  builder: (_) => PlanBuilderSheet(api: api),
);

class PlanBuilderSheet extends StatefulWidget {
  const PlanBuilderSheet({super.key, required this.api});

  final ApiClient api;

  @override
  State<PlanBuilderSheet> createState() => _PlanBuilderSheetState();
}

class _PlanBuilderSheetState extends State<PlanBuilderSheet> {
  static const int _maxQty = 30; // backend: qty 1..30

  int _qty = 1;
  String _schedule = 'daily';

  /// Regenerated whenever the payload changes so a retry of the same payload
  /// replays, and a changed payload never hits PAYLOAD_MISMATCH (legacy
  /// checkout key discipline).
  String _idemKey = const Uuid().v4();

  List<({String id, String label, String pincode})> _addresses = const [];
  String? _addressId;
  bool _loadingAddresses = true;
  String? _addressError;

  SubscriptionEstimate? _estimate;
  bool _estimateLoading = false;
  String? _estimateError;
  int _estimateSeq = 0;

  bool _submitting = false;
  String? _error;

  bool get _signedOut => !widget.api.hasToken;

  @override
  void initState() {
    super.initState();
    if (!_signedOut) {
      _loadAddresses();
      _refreshEstimate();
    }
  }

  Future<void> _loadAddresses() async {
    try {
      final raw = await widget.api.listAddresses();
      if (!mounted) return;
      final parsed = <({String id, String label, String pincode})>[];
      for (final a in raw.whereType<Map>()) {
        final j = Map<String, dynamic>.from(a);
        final id = (j['id'] ?? '').toString();
        if (id.isEmpty) continue;
        parsed.add((
          id: id,
          label: addressLabelOf(j),
          pincode: (j['pincode'] ?? '').toString(),
        ));
      }
      setState(() {
        _addresses = parsed;
        _addressId = parsed.isEmpty ? null : parsed.first.id;
        _loadingAddresses = false;
        _addressError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingAddresses = false;
        _addressError = e.isOffline
            ? subStrings['offline']
            : e.isServerError
            ? 'Server problem — retry in a moment.'
            : subStrings['loadFailed'];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingAddresses = false;
        _addressError = subStrings['loadFailed'];
      });
    }
  }

  Future<void> _refreshEstimate() async {
    if (_signedOut) return;
    final seq = ++_estimateSeq;
    setState(() {
      _estimateLoading = true;
      _estimateError = null;
    });
    try {
      final raw = await widget.api.subscriptionEstimate(
        qty: _qty,
        skuMix: 'refill', // calculator plans are refill plans (legacy parity)
      );
      final estimate = SubscriptionEstimate.fromApi(raw);
      if (!mounted || seq != _estimateSeq) return;
      setState(() {
        _estimate = estimate;
        _estimateLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _estimateSeq) return;
      setState(() {
        _estimate = null;
        _estimateLoading = false;
        _estimateError = e.isOffline
            ? subStrings['offline']
            : e.isServerError
            ? 'Server problem — retry in a moment.'
            : subStrings['estimateFailed'];
      });
    } catch (_) {
      if (!mounted || seq != _estimateSeq) return;
      setState(() {
        _estimate = null;
        _estimateLoading = false;
        _estimateError = subStrings['estimateFailed'];
      });
    }
  }

  void _setQty(int delta) {
    final next = _qty + delta;
    if (next < 1 || next > _maxQty) return;
    setState(() {
      _qty = next;
      _idemKey = const Uuid().v4();
    });
    _refreshEstimate();
  }

  void _setSchedule(String value) {
    if (value == _schedule) return;
    setState(() {
      _schedule = value;
      _idemKey = const Uuid().v4();
    });
  }

  void _setAddress(String value) {
    if (value == _addressId) return;
    setState(() {
      _addressId = value;
      _idemKey = const Uuid().v4();
    });
  }

  Future<void> _submit() async {
    final addressId = _addressId;
    if (addressId == null || _submitting || _estimate == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await widget.api.createSubscription(
        addressId: addressId,
        qty: _qty,
        skuMix: 'refill',
        window: '', // scheduler-owned window (see file header)
        scheduleType: _schedule,
        recurrence: '',
        idempotencyKey: _idemKey,
      );
      if (!mounted) return;
      Navigator.of(context).pop(res);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        if (e.code == 'PAYLOAD_MISMATCH') {
          _idemKey = const Uuid().v4();
          _error = subStrings['payloadMismatch'];
        } else if (e.isOffline) {
          _error = subStrings['offline'];
        } else if (e.isServerError) {
          _error = 'Server problem — retry in a moment.';
        } else if (e.statusCode == 401) {
          _error = subStrings['signedOutPlan'];
        } else {
          _error = e.message.isNotEmpty
              ? e.message
              : subStrings['createFailed'];
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = subStrings['createFailed'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        !_signedOut &&
        _addressId != null &&
        !_submitting &&
        _estimate != null &&
        !_estimateLoading &&
        _estimateError == null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ShodashaTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      subStrings['planEyebrow']!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: ShodashaTheme.muted,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: subStrings['close'],
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: ShodashaTheme.ink),
                  ),
                ],
              ),
              Text(
                subStrings['planTitle']!,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: ShodashaTheme.ink,
                ),
              ),
              const SizedBox(height: 16),
              if (_signedOut)
                _SignedOutNote()
              else ...[
                _qtyCard(),
                const SizedBox(height: 16),
                _eyebrow(subStrings['rhythm']!),
                const SizedBox(height: 8),
                _scheduleChips(),
                const SizedBox(height: 16),
                _eyebrow(subStrings['address']!),
                const SizedBox(height: 8),
                _addressSection(),
                const SizedBox(height: 16),
                _estimateCard(),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ShodashaTheme.danger,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    // Plan start is not a charge — teal, never money green.
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ShodashaTheme.teal,
                      foregroundColor: ShodashaTheme.surface,
                    ),
                    onPressed: canSubmit ? _submit : null,
                    child: Text(
                      _submitting
                          ? subStrings['starting']!
                          : subStrings['startPlan']!,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _eyebrow(String text) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.4,
      color: ShodashaTheme.muted,
    ),
  );

  Widget _qtyCard() => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
    decoration: BoxDecoration(
      color: ShodashaTheme.surface,
      border: Border.all(color: ShodashaTheme.border),
      borderRadius: BorderRadius.circular(ShodashaTheme.radius),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subStrings['jarsPerDelivery']!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ShodashaTheme.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subStrings['jarSku']!,
                style: const TextStyle(
                  fontSize: 11,
                  color: ShodashaTheme.muted,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: subStrings['removeJar'],
          onPressed: _qty > 1 ? () => _setQty(-1) : null,
          icon: const Icon(
            Icons.remove_circle_outline,
            color: ShodashaTheme.teal,
          ),
        ),
        Text(
          '$_qty',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: ShodashaTheme.ink,
          ),
        ),
        IconButton(
          tooltip: subStrings['addJar'],
          onPressed: _qty < _maxQty ? () => _setQty(1) : null,
          icon: const Icon(Icons.add_circle_outline, color: ShodashaTheme.teal),
        ),
      ],
    ),
  );

  Widget _scheduleChips() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final entry in const [
        ('daily', 'daily'),
        ('alternate', 'alternate'),
        ('weekly', 'weekly'),
      ])
        ChoiceChip(
          label: Text(subStrings[entry.$2]!),
          selected: _schedule == entry.$1,
          selectedColor: ShodashaTheme.tealTint,
          checkmarkColor: ShodashaTheme.teal,
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _schedule == entry.$1
                ? ShodashaTheme.tealDeep
                : ShodashaTheme.ink,
          ),
          onSelected: (_) => _setSchedule(entry.$1),
        ),
    ],
  );

  Widget _addressSection() {
    if (_loadingAddresses) {
      return Container(
        height: ShodashaTheme.minTarget,
        decoration: BoxDecoration(
          color: ShodashaTheme.tealTint,
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        ),
      );
    }
    if (_addressError != null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              _addressError!,
              style: const TextStyle(fontSize: 12, color: ShodashaTheme.muted),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _loadingAddresses = true;
                _addressError = null;
              });
              _loadAddresses();
            },
            style: TextButton.styleFrom(foregroundColor: ShodashaTheme.teal),
            child: Text(subStrings['retry']!),
          ),
        ],
      );
    }
    if (_addresses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ShodashaTheme.solarTint,
          border: Border.all(color: ShodashaTheme.solarBorder),
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline,
              size: 16,
              color: ShodashaTheme.solarDark,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                subStrings['noAddress']!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ShodashaTheme.onSolar,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: _addressId,
      isExpanded: true,
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: [
        for (final a in _addresses)
          DropdownMenuItem(
            value: a.id,
            child: Text(
              a.pincode.isEmpty ? a.label : '${a.label} • ${a.pincode}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) {
        if (v != null) _setAddress(v);
      },
    );
  }

  Widget _estimateCard() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: ShodashaTheme.tealTint,
      border: Border.all(color: ShodashaTheme.teal.withValues(alpha: 0.25)),
      borderRadius: BorderRadius.circular(ShodashaTheme.radius),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: 18,
              color: ShodashaTheme.teal,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                subStrings['estimateTitle']!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: ShodashaTheme.ink,
                ),
              ),
            ),
          ],
        ),
        if (_estimateLoading)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: ShodashaTheme.teal,
              backgroundColor: ShodashaTheme.surface,
            ),
          )
        else if (_estimateError != null) ...[
          const SizedBox(height: 6),
          Text(
            _estimateError!,
            style: const TextStyle(fontSize: 12, color: ShodashaTheme.muted),
          ),
          TextButton(
            onPressed: _refreshEstimate,
            style: TextButton.styleFrom(foregroundColor: ShodashaTheme.teal),
            child: Text(subStrings['retry']!),
          ),
        ] else if (_estimate != null) ...[
          const SizedBox(height: 8),
          if (_estimate!.waterBillPaise != null)
            _estimateRow(
              subStrings['estimateWater']!,
              _estimate!.waterBillPaise!,
            ),
          if (_estimate!.depositDuePaise != null)
            _estimateRow(
              subStrings['estimateDeposit']!,
              _estimate!.depositDuePaise!,
            ),
          const Divider(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                subStrings['estimateTotal']!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ShodashaTheme.ink,
                ),
              ),
              Text(
                rupeesLabel(_estimate!.totalPaise),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  color: ShodashaTheme.ink,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        Text(
          subStrings['estimateNote']!,
          style: const TextStyle(fontSize: 10.5, color: ShodashaTheme.muted),
        ),
      ],
    ),
  );

  Widget _estimateRow(String label, int paise) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: ShodashaTheme.muted),
          ),
        ),
        Text(
          rupeesLabel(paise),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: ShodashaTheme.ink,
          ),
        ),
      ],
    ),
  );
}

class _SignedOutNote extends StatelessWidget {
  const _SignedOutNote();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: ShodashaTheme.surface,
      border: Border.all(color: ShodashaTheme.border),
      borderRadius: BorderRadius.circular(ShodashaTheme.radius),
    ),
    child: Row(
      children: [
        const Icon(Icons.lock_outline, size: 18, color: ShodashaTheme.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            subStrings['signedOutPlan']!,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ShodashaTheme.ink,
            ),
          ),
        ),
      ],
    ),
  );
}
