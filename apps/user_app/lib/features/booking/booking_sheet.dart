// 005-home-ux — Checkout sheet: address + delivery-type + live window
// slots + pay mode + real order placement.
//
// Slots come from GET /windows (capacity-aware, never hardcoded).
// Pay → placeCheckout (quotes → orders/subs, STALE_QUOTE retried once).
// UPI: real Razorpay refs open the gateway (test key); FAKE-* refs open
// the upi:// intent link. Success is verified via GET /orders/{id} — the
// gateway callback alone never marks paid (contract §4.4).
// ui-checklist Making-a-Payment: methods → processing → confirmation +
// next steps. No emojis, locked palette, 48px targets.

import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../addresses/address_screen.dart';
import 'booking_controller.dart';
import 'checkout_service.dart';
import 'product_detail_sheet.dart';

/// Opens checkout. [address] may be null → user must pick one first.
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
  _Phase _phase = _Phase.loadingSlots;
  String _error = '';
  List<_Slot> _slots = [];
  int _slotIdx = 0;
  String _slotDate = '';
  bool _unserviceable = false;
  Razorpay? _gateway;
  CheckoutResult? _pendingUpi;

  BookingController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    _loadSlots();
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
    if (addr == null) {
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
          .map((w) => _Slot(
                start: (w['start'] ?? '') as String,
                end: (w['end'] ?? '') as String,
              ))
          .where((s) => s.start.isNotEmpty)
          .toList();
      _slotDate = (res['date'] as String?) ?? date;
      _unserviceable = (res['serviceable'] as bool?) == false;
      _slotIdx = 0;
      setState(() => _phase = _Phase.form);
    } on ApiException {
      setState(() {
        _phase = _Phase.form;
        _slots = [];
      });
    } catch (_) {
      setState(() {
        _phase = _Phase.form;
        _slots = [];
      });
    }
  }

  String get _windowStart =>
      _slots.isEmpty ? '' : '${_slotDate}T${_slots[_slotIdx].start}:00';

  String get _windowLabel => _slots.isEmpty
      ? _slotDate
      : '$_slotDate ${_slots[_slotIdx].start}–${_slots[_slotIdx].end}';

  String _errorFor(ApiException e) {
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
        return e.message.isNotEmpty ? e.message : 'Kuch galat hua — retry karein';
    }
  }

  Future<void> _pay() async {
    final addr = widget.address;
    if (addr == null || _slots.isEmpty && c.deliveryType == DeliveryType.once) {
      return;
    }
    if (c.paymentMode == PaymentMode.cod && !c.codAllowed) return;
    setState(() {
      _phase = _Phase.paying;
      _error = '';
    });
    try {
      final result = await placeCheckout(
        api: widget.api,
        controller: c,
        addressId: addr.id,
        windowStart: c.deliveryType == DeliveryType.once ? _windowStart : _windowLabel,
        windowLabel: _windowLabel,
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
        windowLabel:
            note.isEmpty ? pending.windowLabel : '${pending.windowLabel} • $note',
        isSubscription: false,
        providerRef: pending.providerRef,
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
    final addr = widget.address;
    final codOk = c.codAllowed;
    final busy = _phase == _Phase.paying || _phase == _Phase.loadingSlots;
    final canPay = addr != null &&
        !busy &&
        (c.deliveryType != DeliveryType.once || _slots.isNotEmpty) &&
        !(c.paymentMode == PaymentMode.cod && !codOk);
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
              const Text(
                'Checkout',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              const SizedBox(height: 12),
              _AddressRow(address: addr, onChange: widget.onChangeAddress),
              const SizedBox(height: 12),
              const Text(
                'Delivery kaisi ho?',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: DeliveryType.values.map((t) {
                  final selected = t == c.deliveryType;
                  return ChoiceChip(
                    label: Text(deliveryTypeLabels[t]!),
                    selected: selected,
                    onSelected: (_) =>
                        setState(() => c.deliveryType = t),
                    selectedColor: Colors.black,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: Color(0xFFE5E5E5)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              if (c.deliveryType == DeliveryType.once) ...[
                const Text(
                  'Time slot',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 8),
                if (_phase == _Phase.loadingSlots)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_unserviceable)
                  const Text(
                    'Is pincode par delivery nahi — address badlein',
                    style: TextStyle(color: Color(0xFFB91C1C)),
                  )
                else if (_slots.isEmpty)
                  const Text(
                    'Slot load nahi hue — retry karein',
                    style: TextStyle(color: Color(0xFF595959)),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _slots.length; i++)
                        ChoiceChip(
                          label: Text(
                            '${_slots[i].start}–${_slots[i].end}',
                          ),
                          selected: i == _slotIdx,
                          onSelected: (_) =>
                              setState(() => _slotIdx = i),
                          selectedColor: Colors.black,
                          labelStyle: TextStyle(
                            color: i == _slotIdx
                                ? Colors.white
                                : Colors.black,
                            fontWeight: FontWeight.w600,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(
                              color: Color(0xFFE5E5E5),
                            ),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
              ],
              Text(
                'Paani ${rupeesLabel(c.waterBillPaise)} + Deposit '
                '${rupeesLabel(c.depositDuePaise)} = Kul '
                '${rupeesLabel(c.quoteTotalPaise)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _PayChip(
                    label: 'UPI',
                    selected: c.paymentMode == PaymentMode.upi,
                    onTap: () =>
                        setState(() => c.paymentMode = PaymentMode.upi),
                  ),
                  const SizedBox(width: 8),
                  _PayChip(
                    label: 'COD (cash)',
                    selected: c.paymentMode == PaymentMode.cod,
                    enabled: codOk,
                    onTap: codOk
                        ? () => setState(
                              () => c.paymentMode = PaymentMode.cod,
                            )
                        : null,
                  ),
                ],
              ),
              if (!codOk)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Rs 2,000 se zyada / bakaya / 3+ hold par COD nahi — UPI chunein',
                    style: TextStyle(
                      color: Color(0xFF595959),
                      fontSize: 13,
                    ),
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
                      color: Color(0xFFB91C1C),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error,
                        style: const TextStyle(color: Color(0xFFB91C1C)),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canPay ? _pay : null,
                  child: Text(
                    c.deliveryType == DeliveryType.once
                        ? 'Pay • ${rupeesLabel(c.quoteTotalPaise)}'
                        : 'Subscription shuru karein',
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

class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.address, required this.onChange});

  final AddressEntry? address;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final a = address;
    final label = a == null
        ? 'Address chunein (map par pin lagayein)'
        : '${a.label} • ${a.addressLine}, ${a.pincode}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E5E5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Color(0xFF0284C7)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
        color: selected ? const Color(0xFF0284C7) : Colors.white,
        border: Border.all(
          color: selected
              ? const Color(0xFF0284C7)
              : const Color(0xFFE5E5E5),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : Colors.black,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    if (!enabled || onTap == null) {
      return Opacity(opacity: 0.5, child: box);
    }
    return GestureDetector(onTap: onTap, child: box);
  }
}
