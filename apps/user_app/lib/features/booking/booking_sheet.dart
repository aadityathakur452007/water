// 006-auth-flow — Stepper checkout: 1 Address → 2 Schedule → 3 Pay.
//
// Back preserves inputs; each step validates before Next. Schedule:
// once → live window slots (GET /windows capacity); daily/alternate/
// weekly → preset rhythm; custom → table_calendar multi-date pick
// (≤6 dates, recurrence = ISO dates joined, contract ≤64 chars).
// Pay → placeCheckout (quotes → orders/subs, STALE_QUOTE retried once);
// UPI = Razorpay gateway for real refs, upi:// link for FAKE-* refs.
// ui-checklist: Submitting-a-Form (button copy matches purpose, loading,
// success/error) + Making-a-Payment. Locked palette, 48px targets.

import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../addresses/address_screen.dart';
import 'booking_controller.dart';
import 'checkout_service.dart';
import 'product_detail_sheet.dart' show deliveryTypeLabels, deliveryTypeIcons;

/// Opens checkout. [address] may be null → step 1 prompts to pick one.
Future<void> showCheckoutSheet(
  BuildContext context, {
  required BookingController controller,
  required ApiClient api,
  required String razorpayKeyId,
  required AddressEntry? address,
  required VoidCallback onChangeAddress,
  required ValueChanged<CheckoutResult> onDone,
}) {
  controller.ensureIdempotencyKey();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    builder: (_) => _CheckoutSheet(
      controller: controller,
      api: api,
      razorpayKeyId: razorpayKeyId,
      address: address,
      onChangeAddress: onChangeAddress,
      onDone: onDone,
    ),
  );
}

class _Slot {
  const _Slot({required this.start, required this.end});
  final String start;
  final String end;
}

enum _Phase { form, loadingSlots, paying, error }

const List<String> _stepTitles = ['Pata', 'Samay', 'Bhugtan'];

class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet({
    required this.controller,
    required this.api,
    required this.razorpayKeyId,
    required this.address,
    required this.onChangeAddress,
    required this.onDone,
  });

  final BookingController controller;
  final ApiClient api;
  final String razorpayKeyId;
  final AddressEntry? address;
  final VoidCallback onChangeAddress;
  final ValueChanged<CheckoutResult> onDone;

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  int _step = 0;
  _Phase _phase = _Phase.loadingSlots;
  String _error = '';
  List<_Slot> _slots = [];
  int _slotIdx = 0;
  String _slotDate = '';
  bool _unserviceable = false;
  // F3: slots fetch failed (not empty — error). Pay/Aage stay blocked
  // with a LOUD banner + retry; the 08:00 fallback never fires silently.
  bool _slotsFailed = false;
  // F5: server first-cycle amount for subscriptions (Pay shows this,
  // never client math). Null until loaded; failure falls back to the
  // client estimate marked lagbhag.
  int? _serverTotal;
  bool _estimateLoading = false;
  bool _estimateFailed = false;

  /// Schedule ask-once: home pre-selects; checkout shows a read-only
  /// recap with Badlein (no re-ask). Once-orders collapse to
  /// Address → Pay (schedule step only for recurring).
  List<String> get _titles =>
      _isOnce ? const ['Pata', 'Bhugtan'] : _stepTitles;
  int get _payStepIdx => _isOnce ? 1 : 2;

  /// Recap editor toggle (once pay step): chips appear only on tap.
  bool _editSchedule = false;
  Razorpay? _gateway;
  CheckoutResult? _pendingUpi;

  /// Custom-schedule picked dates (date-only, ≤6 for the 64-char field).
  final Set<DateTime> _customDays = {};
  DateTime _focusedDay = DateTime.now();

  BookingController get c => widget.controller;
  bool get _isOnce => c.deliveryType == DeliveryType.once;
  bool get _isCustom => c.deliveryType == DeliveryType.custom;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    _loadSlots();
    if (!_isOnce) _fetchEstimate();
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    _gateway?.clear();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSlots() async {
    final addr = widget.address;
    if (addr == null || !_isOnce) {
      setState(() => _phase = _Phase.form);
      return;
    }
    setState(() => _phase = _Phase.loadingSlots);
    try {
      final day = nextServiceableDay(DateTime.now());
      final date = ApiClient.dateOnly(day);
      final res = await widget.api.windows(date: date, pincode: addr.pincode);
      final raw = (res['windows'] as List?) ?? [];
      _slots = raw
          .whereType<Map>()
          .map(
            (w) => _Slot(
              start: (w['start'] ?? '') as String,
              end: (w['end'] ?? '') as String,
            ),
          )
          .where((s) => s.start.isNotEmpty)
          .toList();
      _slotDate = (res['date'] as String?) ?? date;
      _unserviceable = (res['serviceable'] as bool?) == false;
      _slotIdx = 0;
      _slotsFailed = false;
      setState(() => _phase = _Phase.form);
    } on ApiException {
      setState(() {
        _phase = _Phase.form;
        _slots = [];
        _slotsFailed = true;
      });
    } catch (_) {
      setState(() {
        _phase = _Phase.form;
        _slots = [];
        _slotsFailed = true;
      });
    }
  }

  // 014: never send blank window_start (backend min_length=1 → 400).
  // Slots mint the ISO; fallback is serviceable-day 08:00.
  String get _windowStart {
    if (_slots.isNotEmpty) return '${_slotDate}T${_slots[_slotIdx].start}:00';
    final day = _slotDate.isNotEmpty
        ? _slotDate
        : ApiClient.dateOnly(nextServiceableDay(DateTime.now()));
    return '${day}T08:00:00';
  }

  // 014: single fixed promise — Subah 8–12. Slots still load to mint a
  // valid window_start ISO, but the user never picks times.
  String get _windowLabel {
    if (_isOnce) {
      return _slotDate.isEmpty ? 'Subah 8–12' : '$_slotDate Subah 8–12';
    }
    if (_isCustom) {
      final days = _customDays.toList()..sort();
      return days.map(ApiClient.dateOnly).join(',');
    }
    return deliveryTypeLabels[c.deliveryType]!;
  }

  /// F5: first-cycle server amount (one fetch per sheet-open; retries
  /// on demand). Client math stays only as the marked fallback.
  Future<void> _fetchEstimate() async {
    if (_isOnce || _estimateLoading || _serverTotal != null) return;
    setState(() {
      _estimateLoading = true;
      _estimateFailed = false;
    });
    try {
      final res = await widget.api.subscriptionEstimate(
        qty: c.totalJars,
        skuMix: skuMixOf(refill: c.refillQty, container: c.containerQty),
      );
      if (!mounted) return;
      setState(() {
        _serverTotal = (res['total'] as num?)?.toInt();
        _estimateLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _estimateLoading = false;
        _estimateFailed = true;
      });
    }
  }

  String _subPayLabel() {
    final server = _serverTotal;
    if (server != null) return 'Subscription • ${rupeesLabel(server)}';
    if (_estimateLoading) return 'Subscription shuru karein…';
    if (_estimateFailed) {
      return 'Subscription • lagbhag ${rupeesLabel(c.quoteTotalPaise)}';
    }
    return 'Subscription shuru karein';
  }

  String get _recurrence {
    if (!_isCustom) return '';
    final days = _customDays.toList()..sort();
    return days.map(ApiClient.dateOnly).join(',');
  }

  bool get _stepValid {
    if (_step == 0) return widget.address != null;
    if (_step == _payStepIdx) return true;
    // Schedule step (recurring only — once collapses to Address → Pay).
    if (_isCustom) return _customDays.isNotEmpty;
    return true;
  }

  void _next() {
    if (!_stepValid || _step >= _payStepIdx) return;
    if (_step == 0 && _isOnce && _phase != _Phase.loadingSlots) _loadSlots();
    setState(() => _step++);
    if (_step == _payStepIdx && !_isOnce) _fetchEstimate();
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  String _errorFor(ApiException e) {
    // 403 (role/suspended) and 429 (rate limit) get their own guidance —
    // never the generic wall (a11y: distinct, actionable copy).
    if (e.statusCode == 403) {
      return e.message.isNotEmpty
          ? e.message
          : 'Ye action allowed nahi — support se baat karein';
    }
    if (e.statusCode == 429 || e.code == 'RATE_LIMITED') {
      return 'Bahut koshish ho gayi — thodi der me retry karein';
    }
    switch (e.code) {
      case 'NETWORK':
        return 'Internet nahi — dobara try karein';
      case 'STALE_QUOTE':
        return 'Daam badal gaya — dobara try karein';
      case 'OVER_LIMIT':
        return '5 se zyada jar ghar par nahi — quantity kam karein';
      case 'HOLD_BLOCKED':
        return '3 se zyada jar hold par — UPI chunein ya dues chukayein';
      case 'UNAUTH':
        return 'Login chahiye — dobara login karein';
      default:
        return e.message.isNotEmpty
            ? e.message
            : 'Kuch galat hua — retry karein';
    }
  }

  Future<void> _pay() async {
    final addr = widget.address;
    if (addr == null || !_stepValid) return;
    if (c.paymentMode == PaymentMode.cod && !c.codAllowed) return;
    setState(() {
      _phase = _Phase.paying;
      _error = '';
    });
    // F6: re-resolve identity — the address may have been edited or
    // deleted while the sheet was open. Fetch failure passes through
    // (offline never blocks; the server revalidates at create).
    try {
      final listed = await widget.api.listAddresses();
      if (!addressStillListed(listed, addr.id)) {
        if (!mounted) return;
        setState(() {
          _phase = _Phase.error;
          _error = 'Address badal gaya — peeche jakar dobara chunein';
        });
        return;
      }
    } catch (_) {
      // fall through to checkout (server is the enforcer)
    }
    try {
      final result = await placeCheckout(
        api: widget.api,
        controller: c,
        addressId: addr.id,
        windowStart: _isOnce ? _windowStart : _windowLabel,
        windowLabel: _windowLabel,
        recurrence: _recurrence,
        addressLabel: '${addr.label} • ${addr.addressLine}',
      );
      if (!mounted) return;
      if (result.isSubscription || c.paymentMode == PaymentMode.cod) {
        widget.onDone(result);
        return;
      }
      await _collectUpi(result);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = _errorFor(e);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = 'Kuch galat hua — retry karein';
        });
      }
    }
  }

  /// UPI collection: real Razorpay ref → gateway; FAKE-* → upi:// link.
  Future<void> _collectUpi(CheckoutResult result) async {
    if (result.providerRef.isEmpty) {
      widget.onDone(result);
      return;
    }
    if (!result.needsGateway) {
      final ok = await launchUrl(
        Uri.parse(
          'upi://pay?pa=shodasha@upi&pn=Shodasha&am=${result.totalPaise / 100}&cu=INR&tr=${result.providerRef}',
        ),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _phase = _Phase.error;
          _error = 'UPI app nahi mila — COD chunein ya retry karein';
        });
        return;
      }
      widget.onDone(result);
      return;
    }
    if (widget.razorpayKeyId.isEmpty) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = 'Online payment abhi setup nahi — COD chunein';
        });
      }
      return;
    }
    _pendingUpi = result;
    _gateway ??= Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onGatewaySuccess)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _onGatewayError);
    _gateway!.open({
      'key': widget.razorpayKeyId,
      'order_id': result.providerRef,
      'amount': result.totalPaise,
      'currency': 'INR',
      'name': 'Shodasha',
      'description': 'Paani order ${result.orderId}',
    });
  }

  Future<void> _onGatewaySuccess(PaymentSuccessResponse _) async {
    final pending = _pendingUpi;
    if (pending == null || !mounted) return;
    String note = '';
    try {
      final fresh = await widget.api.getOrder(pending.orderId);
      final data = (fresh['order'] as Map<String, dynamic>?) ?? fresh;
      final status = (data['payment_status'] ?? '') as String;
      if (status != 'paid_upi') {
        note = 'Payment bheja gaya — confirm ho raha hai';
      }
    } catch (_) {
      note = 'Payment bheja gaya — confirm ho raha hai';
    }
    if (!mounted) return;
    widget.onDone(
      CheckoutResult(
        orderId: pending.orderId,
        totalPaise: pending.totalPaise,
        windowLabel: note.isEmpty
            ? pending.windowLabel
            : '${pending.windowLabel} • $note',
        isSubscription: false,
        providerRef: pending.providerRef,
        waterPaise: pending.waterPaise,
        depositPaise: pending.depositPaise,
        capsPaise: pending.capsPaise,
        addressLabel: pending.addressLabel,
      ),
    );
  }

  void _onGatewayError(PaymentFailureResponse resp) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.error;
      _error = resp.message?.isNotEmpty == true
          ? resp.message!
          : 'Payment fail ho gaya — retry karein ya COD chunein';
    });
  }

  @override
  Widget build(BuildContext context) {
    final busy = _phase == _Phase.paying || _phase == _Phase.loadingSlots;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepHeader(step: _step, titles: _titles),
              const SizedBox(height: 16),
              if (_step == 0)
                _AddressRow(
                  address: widget.address,
                  onChange: widget.onChangeAddress,
                )
              else if (_step == _payStepIdx)
                _payStep(busy)
              else
                _scheduleStep(busy),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_step > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy ? null : _back,
                        child: const Text('Peeche'),
                      ),
                    ),
                  if (_step > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _step < _payStepIdx
                        ? ElevatedButton(
                            onPressed: (_stepValid && !busy) ? _next : null,
                            child: const Text('Aage badhein'),
                          )
                        : ElevatedButton(
                            onPressed: _canPay(busy) ? _pay : null,
                            child: Text(
                              c.deliveryType == DeliveryType.once
                                  ? 'Bhugtan • ${rupeesLabel(c.quoteTotalPaise)}'
                                  : _subPayLabel(),
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _canPay(bool busy) {
    if (widget.address == null || busy || !_stepValid) return false;
    if (c.paymentMode == PaymentMode.cod && !c.codAllowed) return false;
    // F3: once-orders need loaded slots (banner + retry live in the
    // schedule recap below) — never a silent 08:00 commit.
    if (_isOnce && _slotsFailed) return false;
    return true;
  }

  /// Schedule chips (shared by the recurring step and the once recap
  /// editor — one picker, no duplicated option lists).
  Widget _scheduleChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: DeliveryType.values.map((t) {
        final selected = t == c.deliveryType;
        return ChoiceChip(
          avatar: Icon(
            deliveryTypeIcons[t],
            size: 18,
            color: selected ? ShodashaTheme.bg : ShodashaTheme.blue,
          ),
          label: Text(deliveryTypeLabels[t]!),
          selected: selected,
          onSelected: (_) {
            setState(() {
              c.deliveryType = t;
              _editSchedule = false;
            });
            if (t != DeliveryType.once) _fetchEstimate();
          },
          selectedColor: ShodashaTheme.ink,
          labelStyle: TextStyle(
            color: selected ? ShodashaTheme.bg : ShodashaTheme.ink,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: ShodashaTheme.border),
          ),
        );
      }).toList(),
    );
  }

  /// F3 slots-failure row (banner + retry) — shared by the schedule
  /// step and the once pay recap.
  Widget _slotsFailureRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Slots load nahi hue — time pakka nahi hua',
              style: TextStyle(color: ShodashaTheme.danger),
            ),
          ),
          TextButton(
            onPressed: _loadSlots,
            child: const Text('Dobara try karein'),
          ),
        ],
      ),
    );
  }

  /// Once-order schedule recap (read-only home prefill + Badlein —
  /// the schedule is chosen once, never re-asked).
  Widget _scheduleRecap() {
    final when = _slotDate.isEmpty ? 'Subah 8–12' : '$_slotDate Subah 8–12';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ShodashaTheme.blueTint,
            borderRadius: BorderRadius.circular(ShodashaTheme.radius),
          ),
          child: Row(
            children: [
              const Icon(Icons.wb_sunny_outlined, color: ShodashaTheme.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${deliveryTypeLabels[c.deliveryType]} • $when',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _editSchedule = !_editSchedule),
                child: const Text('Badlein'),
              ),
            ],
          ),
        ),
        if (_editSchedule) ...[const SizedBox(height: 8), _scheduleChips()],
        if (_unserviceable)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Is pincode par delivery nahi — address badlein',
              style: TextStyle(color: ShodashaTheme.danger),
            ),
          ),
        if (_slotsFailed) _slotsFailureRow(),
      ],
    );
  }

  Widget _scheduleStep(bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _scheduleChips(),
        const SizedBox(height: 12),
        if (_isCustom) ...[
          TableCalendar<DateTime>(
            firstDay: DateTime.now(),
            lastDay: DateTime.now().add(const Duration(days: 60)),
            focusedDay: _focusedDay,
            calendarFormat: CalendarFormat.month,
            availableCalendarFormats: const {CalendarFormat.month: 'Mahina'},
            headerStyle: const HeaderStyle(formatButtonVisible: false),
            selectedDayPredicate: (d) => _customDays.any(isSameDayCompat(d)),
            onDaySelected: (selected, focused) {
              setState(() {
                _focusedDay = focused;
                final day = DateTime(
                  selected.year,
                  selected.month,
                  selected.day,
                );
                if (_customDays.any(isSameDayCompat(day))) {
                  _customDays.removeWhere(isSameDayCompat(day));
                } else if (_customDays.length < 6) {
                  _customDays.add(day);
                }
              });
            },
            calendarStyle: CalendarStyle(
              selectedDecoration: const BoxDecoration(
                color: ShodashaTheme.ink,
                shape: BoxShape.circle,
              ),
              todayDecoration: BoxDecoration(
                color: ShodashaTheme.blue.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Text(
            _customDays.isEmpty
                ? 'Delivery wali tareekhein chunein (zyada se zyada 6)'
                : '${_customDays.length} tareekh chuni',
            style: const TextStyle(fontSize: 13, color: ShodashaTheme.muted),
          ),
        ] else ...[
          const Text(
            'Subscription banega — pause/skip kabhi bhi kar sakte hain.',
            style: TextStyle(fontSize: 13, color: ShodashaTheme.blue),
          ),
        ],
      ],
    );
  }

  Widget _payStep(bool busy) {
    final codOk = c.codAllowed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Collapsed schedule: once-orders recap here (Badlein edits
        // inline); recurring chose on the schedule step.
        if (_isOnce) ...[_scheduleRecap(), const SizedBox(height: 12)],
        Text(
          'Paani ${rupeesLabel(c.waterBillPaise)} + Deposit '
          '${rupeesLabel(c.depositDuePaise)} = Kul '
          '${rupeesLabel(c.quoteTotalPaise)}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        // F5: server amount failed → marked client estimate + retry.
        if (!_isOnce && _estimateFailed)
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Server daam nahi aaya — anumanit rashi',
                  style: TextStyle(fontSize: 13, color: ShodashaTheme.muted),
                ),
              ),
              TextButton(
                onPressed: _fetchEstimate,
                child: const Text('Dobara try karein'),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            _PayChip(
              label: 'UPI',
              selected: c.paymentMode == PaymentMode.upi,
              onTap: () => setState(() => c.paymentMode = PaymentMode.upi),
            ),
            const SizedBox(width: 8),
            _PayChip(
              label: 'COD (cash)',
              selected: c.paymentMode == PaymentMode.cod,
              enabled: codOk,
              onTap: codOk
                  ? () => setState(() => c.paymentMode = PaymentMode.cod)
                  : null,
            ),
          ],
        ),
        if (!codOk)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Rs 2,000 se zyada / bakaya / 3+ hold par COD nahi — UPI chunein',
              style: TextStyle(color: ShodashaTheme.muted, fontSize: 13),
            ),
          ),
        if (_phase == _Phase.paying) ...[
          const SizedBox(height: 12),
          const Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Order lag raha hai…'),
            ],
          ),
        ],
        if (_phase == _Phase.error) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.error_outline,
                size: 18,
                color: ShodashaTheme.danger,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error,
                  style: const TextStyle(color: ShodashaTheme.danger),
                ),
              ),
              TextButton(
                onPressed: busy ? null : _pay,
                child: const Text('Retry karein'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Date-only equality ( avoids importing collection helpers).
bool Function(DateTime) isSameDayCompat(DateTime a) =>
    (DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step, required this.titles});

  final int step;
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < titles.length; i++) ...[
          _Dot(index: i, current: step),
          const SizedBox(width: 6),
          Text(
            titles[i],
            style: TextStyle(
              fontWeight: i == step ? FontWeight.w700 : FontWeight.w500,
              color: i <= step ? ShodashaTheme.ink : ShodashaTheme.muted,
              fontSize: 13,
            ),
          ),
          if (i < titles.length - 1) ...[
            const SizedBox(width: 6),
            const Expanded(
              child: Divider(color: ShodashaTheme.border, thickness: 2),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.index, required this.current});

  final int index;
  final int current;

  @override
  Widget build(BuildContext context) {
    final done = index < current;
    final active = index == current;
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active || done ? ShodashaTheme.ink : ShodashaTheme.bg,
        border: Border.all(
          color: active || done ? ShodashaTheme.ink : ShodashaTheme.border,
        ),
        shape: BoxShape.circle,
      ),
      child: done
          ? const Icon(Icons.check, size: 14, color: ShodashaTheme.bg)
          : Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? ShodashaTheme.bg : ShodashaTheme.muted,
              ),
            ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.address, required this.onChange});

  final AddressEntry? address;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final a = address;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: ShodashaTheme.blue),
          const SizedBox(width: 8),
          Expanded(
            // F7: two lines — label/pincode + house/street/area detail.
            child: a == null
                ? const Text('Address chunein (map par pin lagayein)')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${a.label} • ${a.pincode}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        addressDetailLine(a),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: ShodashaTheme.muted,
                        ),
                      ),
                    ],
                  ),
          ),
          TextButton(onPressed: onChange, child: const Text('Badlein')),
        ],
      ),
    );
  }
}

class _PayChip extends StatelessWidget {
  const _PayChip({
    required this.label,
    required this.selected,
    this.enabled = true,
    this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: selected ? ShodashaTheme.blue : ShodashaTheme.bg,
        border: Border.all(
          color: selected ? ShodashaTheme.blue : ShodashaTheme.border,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? ShodashaTheme.bg : ShodashaTheme.ink,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    // a11y-1: explicit semantics — a disabled chip announces as
    // unavailable (never a focusable dead end); enabled chips are
    // buttons with selected state.
    if (!enabled || onTap == null) {
      return Opacity(
        opacity: 0.5,
        child: Semantics(
          button: true,
          enabled: false,
          label: '$label — uplabdh nahi',
          child: ExcludeSemantics(child: box),
        ),
      );
    }
    return Semantics(
      button: true,
      enabled: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(onTap: onTap, child: box),
      ),
    );
  }
}
