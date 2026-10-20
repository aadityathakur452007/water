// S7 — jar-return sheet: qty + pickup address + UPI id → POST /v1/returns.
//
// Address selection is injected (nullable) so this feature never imports the
// addresses slice; when the host cannot supply a picker the sheet says so and
// keeps submit disabled instead of asking users to type database ids.
// Refund amount, SLA and request id all come from the server response.

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
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

class ReturnSheet extends StatefulWidget {
  const ReturnSheet({super.key, required this.api, this.pickAddress});

  final ApiClient api;
  final ReturnAddressPicker? pickAddress;

  @override
  State<ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<ReturnSheet> {
  late final ReturnsController _controller = ReturnsController(api: widget.api);
  final TextEditingController _upi = TextEditingController();
  ReturnAddress? _address;
  int _qty = 1;

  bool get _valid => _address != null && _upi.text.trim().isNotEmpty;

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
    final ok = await _controller.submit(
      qty: _qty,
      addressId: _address!.id,
      upiId: _upi.text.trim(),
    );
    if (!mounted || !ok) return;
    Navigator.of(context).pop(_controller.lastRequest); // null-safe at caller
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => Column(
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
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _controller.busy
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: ShodashaTheme.muted),
                  ),
                ],
              ),
              const Text(
                'Pickup + refund in 10 working days.',
                style: TextStyle(fontSize: 13, color: ShodashaTheme.muted),
              ),
              const SizedBox(height: 18),
              const Text(
                'HOW MANY JARS ARE YOU RETURNING?',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: ShodashaTheme.muted,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  IconButton.outlined(
                    tooltip: 'Remove one jar',
                    onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      '$_qty',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: ShodashaTheme.ink,
                      ),
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: 'Add one jar',
                    onPressed: _qty < 10 ? () => setState(() => _qty++) : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'PICKUP ADDRESS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: ShodashaTheme.muted,
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
                decoration: const InputDecoration(
                  labelText: 'UPI ID (for deposit refund)',
                  hintText: 'name@bank',
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
                  ],
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_controller.busy || !_valid) ? null : _send,
                  child: _controller.busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ShodashaTheme.surface,
                          ),
                        )
                      : const Text('Send request'),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Deposit is refunded after the jars are collected.',
                style: TextStyle(fontSize: 11, color: ShodashaTheme.muted),
              ),
            ],
          ),
        ),
      ),
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
