// S7 — jar-return sheet: qty + pickup address + UPI id → POST /v1/returns.
//
// Address selection is injected (nullable) so this feature never imports the
// addresses slice; when the host cannot supply a picker the sheet says so and
// keeps submit disabled instead of asking users to type database ids.
// Refund amount, SLA and request id all come from the server response.

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../shared/ui/app_button.dart';
import '../../shared/ui/app_icon_button.dart';
import 'returns_controller.dart';

/// One address chosen by the host app (id + human label for the sheet).
@immutable
class ReturnAddress {
  const ReturnAddress({required this.id, required this.label});

  final String id;
  final String label;
}

/// Injected picker. The shell/addresses slice shows its own picker and maps
/// the result; returns stays free of cross-feature imports.
typedef ReturnAddressPicker =
    Future<ReturnAddress?> Function(BuildContext context);

/// Minimal UPI VPA check: `localpart@handle`, no spaces. Tolerant of bank
/// handles (`@okhdfcbank`, `@ybl`) and dots/dashes in the local part.
final RegExp _upiVpa = RegExp(
  r'^[a-zA-Z0-9._-]{2,256}@[a-zA-Z][a-zA-Z0-9.]{1,64}$',
);

/// True when [value] looks like a refundable UPI id (server-side truth).
bool isValidUpi(String value) => _upiVpa.hasMatch(value.trim());

class ReturnSheet extends StatefulWidget {
  const ReturnSheet({
    super.key,
    required this.api,
    this.pickAddress,
    this.heldJars = 10,
  });

  final ApiClient api;
  final ReturnAddressPicker? pickAddress;

  /// Jars currently held by the customer; the return quantity never exceeds it.
  final int heldJars;

  @override
  State<ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<ReturnSheet> {
  late final ReturnsController _controller = ReturnsController(api: widget.api);
  final TextEditingController _upi = TextEditingController();
  ReturnAddress? _address;
  late int _qty = widget.heldJars > 0 ? 1 : 0;

  int get _maxQty => widget.heldJars.clamp(0, 30);

  bool get _valid =>
      _address != null && isValidUpi(_upi.text) && _qty >= 1 && _qty <= _maxQty;

  @override
  void dispose() {
    _upi.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickAddress() async {
    final pick = widget.pickAddress;
    if (pick == null) return;
    final picked = await pick(context);
    if (!mounted || picked == null) return;
    setState(() => _address = picked);
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    await _controller.submit(
      qty: _qty,
      addressId: _address!.id,
      upiId: _upi.text.trim(),
    );
    // Success stays in the sheet to show the server request id + SLA.
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_controller.busy,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final done = _controller.lastRequest;
              if (done != null) return _success(done);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: ShodashaTheme.border,
                        borderRadius: BorderRadius.circular(
                          ShodashaTheme.radiusSm,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Return jars',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: ShodashaTheme.ink,
                          ),
                        ),
                      ),
                      AppIconButton(
                        tooltip: 'Close',
                        icon: Icons.close,
                        onPressed: _controller.busy
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const Text(
                    'Pickup + refund in 10 working days.',
                    style: TextStyle(fontSize: 13, color: ShodashaTheme.muted),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'How many jars are you returning?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ShodashaTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      IconButton.outlined(
                        tooltip: 'Remove one jar',
                        onPressed: _qty > 1
                            ? () => setState(() => _qty--)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          '$_qty',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: ShodashaTheme.ink,
                          ),
                        ),
                      ),
                      IconButton.outlined(
                        tooltip: 'Add one jar',
                        onPressed: _qty < _maxQty
                            ? () => setState(() => _qty++)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                      const Spacer(),
                      Text(
                        '$_maxQty held',
                        style: const TextStyle(
                          fontSize: 12,
                          color: ShodashaTheme.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  if (_maxQty == 0) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'You have no empty jars to return.',
                      style: TextStyle(
                        fontSize: 12,
                        color: ShodashaTheme.muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Text(
                    'Pickup address',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ShodashaTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _AddressCard(
                    address: _address,
                    enabled: widget.pickAddress != null && !_controller.busy,
                    unavailable: widget.pickAddress == null,
                    onTap: _pickAddress,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _upi,
                    enabled: !_controller.busy,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      labelText: 'UPI ID for deposit refund',
                      hintText: 'name@bank',
                      errorText:
                          _upi.text.trim().isNotEmpty && !isValidUpi(_upi.text)
                          ? 'Enter a valid UPI ID like name@bank'
                          : null,
                      helperText:
                          'Your deposit refund is sent to this UPI after pickup.',
                    ),
                  ),
                  if (_controller.error != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 16,
                          color: ShodashaTheme.danger,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _controller.error!,
                            style: const TextStyle(
                              color: ShodashaTheme.danger,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (_controller.isAuthError)
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Sign in again'),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  AppButton(
                    label: 'Send request',
                    busy: _controller.busy,
                    onPressed: (_controller.busy || !_valid) ? null : _send,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Deposit is refunded after the jars are collected.',
                    style: TextStyle(fontSize: 11, color: ShodashaTheme.muted),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _success(ReturnRequest request) {
    final refund = request.refundPaise;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: ShodashaTheme.border,
              borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Row(
          children: [
            Icon(Icons.check_circle, color: ShodashaTheme.success, size: 30),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Return requested',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: ShodashaTheme.ink,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          request.message.isEmpty
              ? 'Pickup within 10 working days.'
              : request.message,
          style: const TextStyle(
            fontSize: 13,
            height: 1.4,
            color: ShodashaTheme.muted,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ShodashaTheme.bg,
            borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            border: Border.all(color: ShodashaTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Request ID',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ShodashaTheme.muted,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                request.id,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: ShodashaTheme.ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${request.qty} jar${request.qty == 1 ? '' : 's'} · '
                'Pickup by ${request.slaDue.isEmpty ? 'support will confirm' : request.slaDue}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: ShodashaTheme.muted,
                ),
              ),
              if (refund != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Refund recorded: ${formatInr(refund)}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.greenDark,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        AppButton(
          label: 'Done',
          onPressed: () => Navigator.of(context).pop(request),
        ),
        const SizedBox(height: 8),
        const Text(
          'Keep this request id for support. Refund is sent after pickup.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: ShodashaTheme.muted),
        ),
      ],
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.address,
    required this.enabled,
    required this.unavailable,
    required this.onTap,
  });

  final ReturnAddress? address;
  final bool enabled;
  final bool unavailable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      constraints: const BoxConstraints(minHeight: ShodashaTheme.minTarget),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_outlined, color: ShodashaTheme.teal),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              unavailable
                  ? 'Address selection is unavailable. Add or select an address from Profile first.'
                  : (address?.label ?? 'Choose pickup address'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: address == null ? FontWeight.w500 : FontWeight.w700,
                color: unavailable || address == null
                    ? ShodashaTheme.muted
                    : ShodashaTheme.ink,
              ),
            ),
          ),
          if (!unavailable && enabled)
            const Icon(Icons.chevron_right, color: ShodashaTheme.muted),
        ],
      ),
    );

    if (unavailable || !enabled) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      onTap: onTap,
      child: content,
    );
  }
}
