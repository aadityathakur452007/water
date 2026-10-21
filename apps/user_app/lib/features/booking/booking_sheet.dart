// Checkout sheet: Address → Schedule (recurring) → Payment.
//
// Money law: the amount shown and sent to the gateway is always the
// server-issued quote (once) or the server first-cycle estimate (recurring).
// There is no client-side payable math and no client-minted UPI link.
//
// UPI: real Razorpay refs open the gateway; FAKE-*/server links open the
// server-issued `upi://` link. After the intent we poll GET /orders/{id}
// at most 5× every 2s for `payment_status == 'paid_upi'`. Unconfirmed →
// honest retry + COD fallback (COD is gated by the contract cap).
//
// Holds contract tunables: COD cap Rs 2,000, hold-block 3, quote TTL 15m.

import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../addresses/address_screen.dart';
import 'booking_controller.dart';
import 'checkout_service.dart';

/// Opens checkout. [address] may be null → step 1 asks for one.
///
/// [onDone] is called with the server-confirmed result while the sheet is
/// still open; the caller closes the sheet and shows its confirmation.
Future<void> showCheckoutSheet(
  BuildContext context, {
  required BookingController controller,
  required ApiClient api,
  required String razorpayKeyId,
  required AddressEntry? address,
  required VoidCallback onChangeAddress,
  required ValueChanged<CheckoutResult> onDone,
}) {
  controller.refreshIdempotencyKey();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ShodashaTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ShodashaTheme.radiusSheet),
      ),
    ),
    clipBehavior: Clip.antiAlias,
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

enum _Phase { form, paying, error }

/// What the error phase may honestly offer. Once an order/subscription
/// exists, create is NEVER re-posted — only the payment step is retried
/// (same idempotency key → server replays the same row).
enum _Recovery {
  none,
  retry, // nothing created — safe to retry create with the same key
  created, // row exists — retry payment / open Orders
  unconfirmed, // payment sent, webhook silent — re-check / open Orders
  checkOnly, // response unusable — review Orders/Subscriptions first
}

const Map<DeliveryType, String> _deliveryLabels = {
  DeliveryType.once: 'One-time',
  DeliveryType.daily: 'Daily plan',
  DeliveryType.alternate: 'Alternate days',
  DeliveryType.weekly: 'Weekly',
  DeliveryType.custom: 'Custom dates',
};

const Map<DeliveryType, IconData> _deliveryIcons = {
  DeliveryType.once: Icons.bolt_outlined,
  DeliveryType.daily: Icons.repeat,
  DeliveryType.alternate: Icons.event_repeat_outlined,
  DeliveryType.weekly: Icons.calendar_view_week_outlined,
  DeliveryType.custom: Icons.date_range_outlined,
};

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
  _Phase _phase = _Phase.form;
  String _error = '';

  bool _loadingSlots = false;
  bool _slotsFailed = false;
  bool _unserviceable = false;
  List<_Slot> _slots = const [];
  int _slotIdx = 0;
  String _slotDate = '';

  /// Server quote for a one-time order (verbatim from POST /quotes).
  Map<String, dynamic>? _quote;
  bool _quoteLoading = false;
  String _quoteError = '';

  /// Server first-cycle total for a recurring checkout.
  int? _subTotal;
  bool _estimateLoading = false;
  String _estimateError = '';

  bool _editSchedule = false;
  final Set<DateTime> _customDays = {};
  DateTime _focusedDay = DateTime.now();

  Razorpay? _gateway;
  CheckoutResult? _pendingUpi;

  /// The created order/subscription. Set as soon as the server confirms it;
  /// the recovery flow never re-posts create while this is non-null.
  CheckoutResult? _placed;
  _Recovery _recovery = _Recovery.none;

  BookingController get c => widget.controller;
  bool get _isOnce => c.deliveryType == DeliveryType.once;
  bool get _isCustom => c.deliveryType == DeliveryType.custom;

  int get _payStepIdx => _isOnce ? 1 : 2;
  List<String> get _titles =>
      _isOnce ? const ['Address', 'Payment'] : const ['Address', 'Schedule', 'Payment'];

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isOnce) {
        _loadSlots();
      } else {
        _fetchEstimate();
      }
    });
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
    if (addr == null || !_isOnce) return;
    setState(() {
      _loadingSlots = true;
      _slotsFailed = false;
      _unserviceable = false;
    });
    try {
      final day = nextServiceableDay(DateTime.now());
      final date = ApiClient.dateOnly(day);
      final res = await widget.api.windows(date: date, pincode: addr.pincode);
      if (!mounted) return;
      final raw = (res['windows'] as List?) ?? const [];
      setState(() {
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
        _loadingSlots = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _slots = const [];
        _slotsFailed = true;
        _loadingSlots = false;
      });
    }
  }

  /// Valid window_start: server slot when loaded; otherwise the fixed
  /// morning promise on a serviceable day. Never blank.
  String get _windowStart {
    if (_slots.isNotEmpty) {
      return '${_slotDate}T${_slots[_slotIdx].start}:00';
    }
    final day = _slotDate.isNotEmpty
        ? _slotDate
        : ApiClient.dateOnly(nextServiceableDay(DateTime.now()));
    return '${day}T08:00:00';
  }

  String get _windowLabel {
    if (_isOnce) {
      return _slotDate.isEmpty
          ? kFixedWindowLabel
          : '$_slotDate • $kFixedWindowLabel';
    }
    if (_isCustom) {
      final days = _customDays.toList()..sort();
      return days.map(ApiClient.dateOnly).join(',');
    }
    return _deliveryLabels[c.deliveryType] ?? 'Recurring';
  }

  String get _recurrence {
    if (!_isCustom) return '';
    final days = _customDays.toList()..sort();
    return days.map(ApiClient.dateOnly).join(',');
  }

  bool get _stepValid {
    if (_step == 0) return widget.address != null;
    if (_step == _payStepIdx) return true;
    if (_isCustom) return _customDays.isNotEmpty;
    return true;
  }

  Future<void> _fetchEstimate() async {
    if (_isOnce || _estimateLoading) return;
    setState(() {
      _estimateLoading = true;
      _estimateError = '';
    });
    try {
      final res = await widget.api.subscriptionEstimate(
        qty: c.totalJars,
        skuMix: skuMixOf(refill: c.refillQty, container: c.containerQty),
      );
      if (!mounted) return;
      final estimate = res['first_cycle_estimate'];
      final total = (res['total'] as num?)?.toInt() ??
          (estimate is Map ? (estimate['total'] as num?)?.toInt() : null);
      setState(() {
        _subTotal = total;
        _estimateError = total == null
            ? 'The server did not return the first-cycle amount. Please retry.'
            : '';
        _estimateLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _estimateLoading = false;
        _estimateError =
            'Could not fetch the first-cycle amount. Please retry.';
      });
    }
  }

  Future<void> _loadQuote() async {
    final addr = widget.address;
    if (!_isOnce || addr == null || _quoteLoading) return;
    setState(() {
      _quoteLoading = true;
      _quoteError = '';
    });
    try {
      final quote = await fetchServerQuote(
        api: widget.api,
        controller: c,
        addressId: addr.id,
        windowStart: _windowStart,
      );
      if (!mounted) return;
      setState(() {
        _quote = quote;
        _quoteLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _quote = null;
        _quoteLoading = false;
        _quoteError = checkoutErrorFor(e);
      });
    } on ServerDataException catch (e) {
      if (!mounted) return;
      setState(() {
        _quote = null;
        _quoteLoading = false;
        _quoteError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _quote = null;
        _quoteLoading = false;
        _quoteError = 'Could not fetch the live price. Please retry.';
      });
    }
  }

  void _next() {
    if (!_stepValid || _step >= _payStepIdx) return;
    if (_step == 0 && _isOnce && !_loadingSlots && _slotsFailed) {
      _loadSlots();
    }
    setState(() => _step++);
    if (_step == _payStepIdx) {
      if (_isOnce) {
        if (_quote == null) _loadQuote();
      } else if (_subTotal == null) {
        _fetchEstimate();
      }
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  bool _canPay(bool busy) {
    if (busy || widget.address == null || !_stepValid) return false;
    if (_isOnce) {
      if (_quote == null ||
          _quoteLoading ||
          _quoteError.isNotEmpty ||
          _slotsFailed ||
          _unserviceable) {
        return false;
      }
      if (c.paymentMode == PaymentMode.cod && !c.codAllowed) return false;
      return true;
    }
    return _subTotal != null && _estimateError.isEmpty;
  }

  Future<void> _pay() async {
    final addr = widget.address;
    if (addr == null || !_stepValid) return;
    if (!_canPay(_phase == _Phase.paying)) return;
    setState(() {
      _phase = _Phase.paying;
      _error = '';
      _recovery = _Recovery.none;
      _placed = null;
    });

    // Address identity: the id the sheet opened with must still exist.
    // Fetch failures pass through — the server revalidates at create.
    try {
      final listed = await widget.api.listAddresses();
      if (!addressStillListed(listed, addr.id)) {
        if (!mounted) return;
        setState(() {
          _phase = _Phase.error;
          _recovery = _Recovery.retry;
          _error = 'This address changed. Go back and choose it again.';
        });
        return;
      }
    } catch (_) {
      // Offline never blocks checkout; the server is the enforcer.
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
        quote: _isOnce ? _quote : null,
      );
      if (!mounted) return;
      _placed = result;
      if (result.isSubscription || c.paymentMode == PaymentMode.cod) {
        c.resetBookingSession();
        widget.onDone(result);
        return;
      }
      if (result.providerRef.isEmpty && result.upiLink.isEmpty) {
        // The order exists; only the payment step failed (caught in
        // placeCheckout, so no throw and no key rotation).
        setState(() {
          _phase = _Phase.error;
          _recovery = _Recovery.created;
          _error = result.attentionMessage.isNotEmpty
              ? result.attentionMessage
              : 'Your order is placed. The payment could not be started — '
                  'retry payment or check Orders.';
        });
        return;
      }
      await _collectUpi(result);
    } on PriceChangedException catch (e) {
      if (!mounted) return;
      setState(() {
        _quote = null;
        _phase = _Phase.error;
        _recovery = _Recovery.retry;
        _error = e.message;
      });
      await _loadQuote();
    } on UnconfirmedCreateException catch (e) {
      // The row may exist but the response was unusable — retrying would
      // create a duplicate, so send the user to Orders/Subscriptions.
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _recovery = _Recovery.checkOnly;
        _error = e.message;
      });
    } on ServerDataException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _recovery = _Recovery.retry;
        _error = e.message;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _recovery = _Recovery.retry;
        _error = checkoutErrorFor(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _recovery = _Recovery.retry;
        _error = 'Something went wrong. Please retry.';
      });
    }
  }

  Future<void> _collectUpi(CheckoutResult result) async {
    // Every branch below runs AFTER the order exists — the key is never
    // rotated and create is never re-posted; only the payment step retries.
    if (result.providerRef.isEmpty && result.upiLink.isEmpty) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _recovery = _Recovery.created;
        _error = result.attentionMessage.isNotEmpty
            ? result.attentionMessage
            : 'Your order is placed. The payment could not be started — '
                'retry payment or check Orders.';
      });
      return;
    }

    if (!result.needsGateway) {
      // Server-issued link only — the client never mints a UPI URI.
      if (result.upiLink.isEmpty) {
        if (!mounted) return;
        setState(() {
          _phase = _Phase.error;
          _recovery = _Recovery.created;
          _error = 'Your order is placed, but the payment link is missing. '
              'Retry payment or check Orders.';
        });
        return;
      }
      bool opened;
      try {
        opened = await launchUrl(
          Uri.parse(result.upiLink),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        opened = false;
      }
      if (!mounted) return;
      if (!opened) {
        setState(() {
          _phase = _Phase.error;
          _recovery = _Recovery.created;
          _error = 'Your order is placed. No UPI app opened — retry the '
              'payment or check Orders.';
        });
        return;
      }
      _pendingUpi = result;
      setState(() => _phase = _Phase.paying);
      await _verifyOrPollPayment(result);
      return;
    }

    if (widget.razorpayKeyId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _recovery = _Recovery.created;
        _error = 'Your order is placed. Online payment is not set up in '
            'this build — check Orders.';
      });
      return;
    }

    _pendingUpi = result;
    _gateway ??= Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onGatewaySuccess)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _onGatewayError)
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    _gateway!.open({
      'key': widget.razorpayKeyId,
      'order_id': result.providerRef,
      'amount': result.totalPaise,
      'currency': 'INR',
      'name': 'Shodasha',
      'description': 'Water order ${result.orderId}',
    });
  }

  /// Retry the payment step for the already-created order: re-request the
  /// intent (same key → server replays the same row) or re-open the payment
  /// that was issued. Never touches create.
  Future<void> _recoverPayment() async {
    final placed = _placed;
    if (placed == null || _phase == _Phase.paying) return;
    if (placed.providerRef.isEmpty && placed.upiLink.isEmpty) {
      await _requestIntent();
    } else {
      await _collectUpi(placed);
    }
  }

  Future<void> _requestIntent() async {
    final placed = _placed;
    if (placed == null) return;
    setState(() {
      _phase = _Phase.paying;
      _error = '';
    });
    final String failCopy = 'The payment link is still unavailable. Try '
        'again or check Orders.';
    try {
      final intent = await widget.api.upiIntent(
        orderId: placed.orderId,
        idempotencyKey: c.ensureIdempotencyKey(),
      );
      final ref = (intent['provider_ref'] ?? '') as String;
      final link = (intent['link'] ?? '') as String;
      if (!mounted) return;
      if (ref.isEmpty && link.isEmpty) {
        setState(() {
          _phase = _Phase.error;
          _recovery = _Recovery.created;
          _error = failCopy;
        });
        return;
      }
      await _collectUpi(placed.withIntent(providerRef: ref, upiLink: link));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _recovery = _Recovery.created;
        _error = failCopy;
      });
    }
  }

  Future<void> _checkPaymentAgain() async {
    final placed = _placed;
    if (placed == null || _phase == _Phase.paying) return;
    setState(() => _phase = _Phase.paying);
    await _verifyOrPollPayment(placed);
  }

  void _checkOrders() {
    final placed = _placed;
    if (placed == null) return;
    // Shell's onDone pops this sheet and shows the confirmation/pending view.
    widget.onDone(placed);
  }

  Future<void> _verifyOrPollPayment(CheckoutResult pending) async {
    for (var i = 0; i < 5; i++) {
      if (!mounted) return;
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      try {
        final fresh = await widget.api.getOrder(pending.orderId);
        final data = (fresh['order'] as Map<String, dynamic>?) ?? fresh;
        final status = (data['payment_status'] ?? '') as String;
        if (status == 'paid_upi') {
          c.resetBookingSession();
          widget.onDone(pending);
          return;
        }
      } catch (_) {
        // Transient error — keep polling.
      }
    }
    if (!mounted) return;
    // Do NOT complete an unconfirmed order and do NOT mint a new key — the
    // order stays placed; the user can re-check or open Orders.
    setState(() {
      _phase = _Phase.error;
      _recovery = _Recovery.unconfirmed;
      _error = 'Payment is not confirmed yet. Your order is placed — check '
          'the payment again or open Orders.';
    });
  }

  Future<void> _onGatewaySuccess(PaymentSuccessResponse _) async {
    final pending = _pendingUpi;
    if (pending == null || !mounted) return;
    setState(() => _phase = _Phase.paying);
    await _verifyOrPollPayment(pending);
  }

  void _onGatewayError(PaymentFailureResponse resp) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.error;
      _recovery = _Recovery.created;
      _error = resp.message?.isNotEmpty == true
          ? resp.message!
          : 'Your order is placed. Payment failed — retry payment or check '
              'Orders.';
    });
  }

  void _onExternalWallet(ExternalWalletResponse _) {
    final pending = _pendingUpi;
    if (pending == null || !mounted) return;
    setState(() => _phase = _Phase.paying);
    _verifyOrPollPayment(pending);
  }

  @override
  Widget build(BuildContext context) {
    final busy = _phase == _Phase.paying || _loadingSlots;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: ShodashaTheme.border,
                      borderRadius:
                          BorderRadius.circular(ShodashaTheme.radiusSm),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
                child: Row(
                  children: [
                    Expanded(child: _StepHeader(step: _step, titles: _titles)),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: ShodashaTheme.muted,
                      ),
                      tooltip: 'Close',
                      onPressed: busy ? null : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_step == 0)
                        _AddressRow(
                          address: widget.address,
                          onChange: widget.onChangeAddress,
                        )
                      else if (_step == _payStepIdx)
                        _payStep(busy)
                      else
                        _scheduleStep(),
                    ],
                  ),
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  color: ShodashaTheme.surface,
                  border: Border(top: BorderSide(color: ShodashaTheme.border)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  children: [
                    if (_step > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: busy ? null : _back,
                          child: const Text('Back'),
                        ),
                      ),
                    if (_step > 0) const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _step < _payStepIdx
                          ? ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: ShodashaTheme.teal,
                                foregroundColor: ShodashaTheme.surface,
                              ),
                              onPressed: (_stepValid && !busy) ? _next : null,
                              child: const Text('Next'),
                            )
                          : ElevatedButton(
                              onPressed: _canPay(busy) ? _pay : null,
                              child: Text(_payLabel),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _payLabel {
    if (_isOnce) {
      final total = c.serverTotalPaise;
      return total == null ? 'PAY' : 'PAY • ${rupeesLabel(total)}';
    }
    final total = _subTotal;
    if (total != null) return 'PAY • ${rupeesLabel(total)}';
    if (_estimateLoading) return 'PAY';
    return 'PAY';
  }

  Widget _scheduleStep() {
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
            availableCalendarFormats: const {CalendarFormat.month: 'Month'},
            headerStyle: const HeaderStyle(formatButtonVisible: false),
            selectedDayPredicate: (d) => _customDays.any(isSameDayCompat(d)),
            onDaySelected: (selected, focused) {
              setState(() {
                _focusedDay = focused;
                final day =
                    DateTime(selected.year, selected.month, selected.day);
                if (_customDays.any(isSameDayCompat(day))) {
                  _customDays.removeWhere(isSameDayCompat(day));
                } else if (_customDays.length < 6) {
                  _customDays.add(day);
                }
                // Dates are part of the create payload → fresh key.
                c.refreshIdempotencyKey();
              });
            },
            calendarStyle: const CalendarStyle(
              selectedDecoration: BoxDecoration(
                color: ShodashaTheme.teal,
                shape: BoxShape.circle,
              ),
              todayDecoration: BoxDecoration(
                color: ShodashaTheme.tealTint,
                shape: BoxShape.circle,
              ),
              todayTextStyle: TextStyle(
                fontWeight: FontWeight.w700,
                color: ShodashaTheme.ink,
              ),
            ),
          ),
          Text(
            _customDays.isEmpty
                ? 'Choose delivery dates (up to 6)'
                : '${_customDays.length} ${_customDays.length == 1 ? 'date' : 'dates'} selected',
            style: const TextStyle(fontSize: 13, color: ShodashaTheme.muted),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ShodashaTheme.tealTint,
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            ),
            child: const Text(
              'A subscription will be created. Pause or skip any time.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ShodashaTheme.ink,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _scheduleChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: DeliveryType.values.map((t) {
        final selected = t == c.deliveryType;
        return ChoiceChip(
          avatar: Icon(
            _deliveryIcons[t],
            size: 18,
            color: selected ? ShodashaTheme.surface : ShodashaTheme.muted,
          ),
          label: Text(_deliveryLabels[t] ?? ''),
          selected: selected,
          onSelected: (_) {
            setState(() => c.deliveryType = t);
            if (t == DeliveryType.once) {
              if (_slots.isEmpty && !_loadingSlots) _loadSlots();
              if (_quote == null) _loadQuote();
            } else if (_subTotal == null) {
              _fetchEstimate();
            }
          },
          backgroundColor: ShodashaTheme.surface,
          selectedColor: ShodashaTheme.teal,
          labelStyle: TextStyle(
            color: selected ? ShodashaTheme.surface : ShodashaTheme.ink,
            fontWeight: FontWeight.w700,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            side: BorderSide(
              color: selected ? ShodashaTheme.teal : ShodashaTheme.border,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _payStep(bool busy) {
    final codOk = c.codAllowed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isOnce) ...[_scheduleRecap(), const SizedBox(height: 12)],
        if (_isOnce) ...[
          _moneyCard(),
          const SizedBox(height: 12),
        ] else ...[
          _estimateCard(),
          const SizedBox(height: 12),
        ],
        if (_isOnce) ...[
          Row(
            children: [
              _PayChip(
                label: 'UPI',
                selected: c.paymentMode == PaymentMode.upi,
                onTap: () => setState(() => c.paymentMode = PaymentMode.upi),
              ),
              const SizedBox(width: 8),
              _PayChip(
                label: 'Cash on delivery',
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
                'Cash on delivery is unavailable over Rs 2,000, with dues, '
                'or with more than 3 jars on hold. Choose UPI.',
                style: TextStyle(color: ShodashaTheme.muted, fontSize: 13),
              ),
            ),
        ] else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ShodashaTheme.tealTint,
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: ShodashaTheme.teal,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'The first cycle is paid online. Later cycles follow your '
                    'delivery schedule.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
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
              Text('Placing your order…'),
            ],
          ),
        ],
        if (_phase == _Phase.error) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ShodashaTheme.danger.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.error_outline,
                    size: 18,
                    color: ShodashaTheme.danger,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _error,
                        style: const TextStyle(
                          color: ShodashaTheme.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (_recovery == _Recovery.retry) ...[
                            OutlinedButton(
                              onPressed: busy ? null : _pay,
                              child: const Text('Retry'),
                            ),
                            if (_isOnce &&
                                codOk &&
                                c.paymentMode == PaymentMode.upi)
                              ElevatedButton(
                                onPressed: busy
                                    ? null
                                    : () {
                                        setState(
                                          () =>
                                              c.paymentMode = PaymentMode.cod,
                                        );
                                        _pay();
                                      },
                                child: const Text('Choose COD'),
                              ),
                          ] else if (_recovery == _Recovery.created) ...[
                            OutlinedButton(
                              onPressed: busy ? null : _recoverPayment,
                              child: const Text('Retry payment'),
                            ),
                            ElevatedButton(
                              onPressed: busy ? null : _checkOrders,
                              child: const Text('Check Orders'),
                            ),
                          ] else if (_recovery == _Recovery.unconfirmed) ...[
                            OutlinedButton(
                              onPressed: busy ? null : _checkPaymentAgain,
                              child: const Text('Check payment again'),
                            ),
                            ElevatedButton(
                              onPressed: busy ? null : _checkOrders,
                              child: const Text('Check Orders'),
                            ),
                          ] else if (_recovery == _Recovery.checkOnly)
                            OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              child: const Text('Close'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _scheduleRecap() {
    final when = _slotDate.isEmpty
        ? kFixedWindowLabel
        : '$_slotDate • $kFixedWindowLabel';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: ShodashaTheme.tealTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wb_sunny_outlined,
                  color: ShodashaTheme.teal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  when,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _editSchedule = !_editSchedule),
                child: const Text('Change'),
              ),
            ],
          ),
          if (_editSchedule) ...[
            const SizedBox(height: 8),
            _scheduleChips(),
          ],
          if (_unserviceable)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: ShodashaTheme.danger,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "We don't deliver to this pincode yet — change your "
                      'address.',
                      style: TextStyle(color: ShodashaTheme.danger),
                    ),
                  ),
                ],
              ),
            ),
          if (_slotsFailed) _slotsFailureRow(),
        ],
      ),
    );
  }

  Widget _slotsFailureRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: ShodashaTheme.danger.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline,
              size: 16,
              color: ShodashaTheme.danger,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Delivery windows did not load — the time is not confirmed.',
                style: TextStyle(color: ShodashaTheme.danger),
              ),
            ),
            TextButton(
              onPressed: _loadingSlots ? null : _loadSlots,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moneyCard() {
    if (_quoteLoading) {
      return const _InfoCard(
        icon: Icons.hourglass_empty,
        text: 'Fetching the live price…',
      );
    }
    if (_quoteError.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ShodashaTheme.danger.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline,
              size: 18,
              color: ShodashaTheme.danger,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _quoteError,
                style: const TextStyle(color: ShodashaTheme.danger),
              ),
            ),
            TextButton(
              onPressed: _loadQuote,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    final total = c.serverTotalPaise;
    if (total == null) {
      return const _InfoCard(
        icon: Icons.hourglass_empty,
        text: 'Waiting for the server price…',
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Water ${rupeesLabel(c.serverWaterPaise ?? 0)} + Deposit '
            '${rupeesLabel(c.serverDepositPaise ?? 0)}',
            style: const TextStyle(fontSize: 13, color: ShodashaTheme.muted),
          ),
          const SizedBox(height: 2),
          Text(
            'Total ${rupeesLabel(total)}',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          if (c.serverQuoteCapNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              c.serverQuoteCapNote,
              style: const TextStyle(fontSize: 12, color: ShodashaTheme.muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _estimateCard() {
    if (_estimateLoading) {
      return const _InfoCard(
        icon: Icons.hourglass_empty,
        text: 'Fetching the first-cycle amount…',
      );
    }
    if (_estimateError.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ShodashaTheme.danger.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline,
              size: 18,
              color: ShodashaTheme.danger,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _estimateError,
                style: const TextStyle(color: ShodashaTheme.danger),
              ),
            ),
            TextButton(
              onPressed: _fetchEstimate,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    final total = _subTotal;
    if (total == null) {
      return const _InfoCard(
        icon: Icons.hourglass_empty,
        text: 'Waiting for the server amount…',
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Text(
        'First cycle ${rupeesLabel(total)}',
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
      ),
    );
  }
}

/// Date-only equality (no collection helpers).
bool Function(DateTime) isSameDayCompat(DateTime a) =>
    (DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShodashaTheme.tealTint,
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: ShodashaTheme.teal),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: ShodashaTheme.ink),
            ),
          ),
        ],
      ),
    );
  }
}

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
              fontWeight: i == step ? FontWeight.w800 : FontWeight.w600,
              color: i <= step ? ShodashaTheme.ink : ShodashaTheme.muted,
              fontSize: i == step ? 14 : 13,
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
        color: active || done ? ShodashaTheme.teal : ShodashaTheme.bg,
        border: Border.all(
          color: active || done ? ShodashaTheme.teal : ShodashaTheme.border,
        ),
        shape: BoxShape.circle,
      ),
      child: done
          ? const Icon(Icons.check, size: 14, color: ShodashaTheme.surface)
          : Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? ShodashaTheme.surface : ShodashaTheme.muted,
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
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: ShodashaTheme.tealTint,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_on,
              color: ShodashaTheme.teal,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: a == null
                ? const Text('Choose a delivery address')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${a.label} • ${a.pincode}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
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
          TextButton(onPressed: onChange, child: const Text('Change')),
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
      constraints: const BoxConstraints(minHeight: ShodashaTheme.minTarget),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: selected ? ShodashaTheme.teal : ShodashaTheme.surface,
        border: Border.all(
          color: selected ? ShodashaTheme.teal : ShodashaTheme.border,
        ),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? ShodashaTheme.surface : ShodashaTheme.ink,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    if (!enabled || onTap == null) {
      return Opacity(
        opacity: 0.5,
        child: Semantics(
          button: true,
          enabled: false,
          label: '$label — unavailable',
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
