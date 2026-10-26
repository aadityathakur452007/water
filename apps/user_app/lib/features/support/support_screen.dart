// S8 — Support: WhatsApp help path, static FAQ, and complaints.
//
// States.md coverage: loading (complaint skeleton), loaded, empty ("no
// complaints yet" with the next action), error (message + retry), form
// default/focused/filled/invalid, submitting, success (snackbar), server 422
// (complaint window closed → WhatsApp path), offline, unauthorized.
//
// Contract: POST /complaints {order_id, reason_code, text <= 500}; no photo
// field in v1 (ADR-017). Windows (24h water quality / 3 days general) are
// enforced by the server — the client never hides a 422.
//
// HARD LAWS: the authenticated ApiClient is injected (ADR-118) — never an
// unauthenticated fallback or 'unknown-device'; WhatsApp digits derive from
// the single kSupportPhone constant; no money, amounts or ticket promises.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import 'support_controller.dart';

/// Static FAQ copy — no money amounts, no invented delivery promises.
const List<({String question, String answer})> _faqs = [
  (
    question: 'How do I schedule a delivery?',
    answer:
        'Pick an available slot on the Home screen before you place your order.',
  ),
  (
    question: 'How do jar returns work?',
    answer:
        'Request a pickup from your profile and add the UPI ID for the refund. '
        'The refund is processed after the jars are collected.',
  ),
  (
    question: 'Which payment methods can I use?',
    answer:
        'Pay by UPI, or choose cash on delivery when your order is eligible.',
  ),
  (
    question: 'Where can I see my payments?',
    answer:
        'Open Payments & deposits from your profile to see server-verified '
        'receipts.',
  ),
];

class SupportScreen extends StatefulWidget {
  const SupportScreen({
    super.key,
    required this.api,
    this.controller,
    this.orderContext,
    this.openUrl,
  });

  /// Authenticated transport from the shell — complaints carry the real
  /// Bearer and persisted X-Device-Id.
  final ApiClient api;

  final SupportController? controller;

  /// Prefilled WhatsApp text when opened from an order (contextual help).
  final String? orderContext;

  /// Injectable for widget tests (defaults to url_launcher's external app).
  final Future<bool> Function(Uri url, {LaunchMode mode})? openUrl;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  late final SupportController _controller =
      widget.controller ?? SupportController(api: widget.api);
  late final bool _ownsController = widget.controller == null;

  @override
  void initState() {
    super.initState();
    if (_ownsController && _controller.status == ComplaintStatus.initial) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _controller.load());
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  Future<void> _openWhatsApp() async {
    // Single source: digits derive from kSupportPhone (ADR-118). Launch is
    // primary; clipboard stays a best-effort fallback, never the main path.
    final digits = kSupportPhone.replaceAll(RegExp(r'\D'), '');
    final text =
        widget.orderContext ??
        'Hi Shodasha support, I need help with my order.';
    final uri = Uri.parse(
      'https://wa.me/$digits?text=${Uri.encodeComponent(text)}',
    );
    final open = widget.openUrl ?? launchUrl;
    bool ok = false;
    try {
      ok = await open(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (ok || !mounted) return;
    unawaited(
      Clipboard.setData(
        ClipboardData(text: kSupportPhone),
      ).then<void>((_) {}, onError: (_) {}),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('WhatsApp did not open — number copied.')),
    );
  }

  Future<void> _openComplaintForm() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ShodashaTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ShodashaTheme.radiusSheet),
        ),
      ),
      builder: (_) => _ComplaintFormSheet(
        controller: _controller,
        onWhatsApp: _openWhatsApp,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShodashaTheme.bg,
      appBar: AppBar(
        title: const Text('Help & support'),
        leading: const BackButton(color: ShodashaTheme.ink),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _HelplineCard(phone: kSupportPhone, onWhatsApp: _openWhatsApp),
          const _SectionLabel('COMMON QUESTIONS'),
          for (final faq in _faqs)
            _Faq(question: faq.question, answer: faq.answer),
          const _SectionLabel('COMPLAINTS'),
          _ComplaintEntryCard(onNewComplaint: _openComplaintForm),
          const SizedBox(height: 20),
          const Text(
            'Your complaints',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: ShodashaTheme.ink,
            ),
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) =>
                _ComplaintsSection(controller: _controller),
          ),
        ],
      ),
    );
  }
}

/// Solid teal helpline banner (donor grammar, gradient flattened). The
/// WhatsApp action is white-on-teal — green stays reserved for money CTAs.
class _HelplineCard extends StatelessWidget {
  const _HelplineCard({required this.phone, required this.onWhatsApp});

  final String phone;
  final VoidCallback onWhatsApp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ShodashaTheme.teal,
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ShodashaTheme.surface.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                ),
                child: const Icon(
                  Icons.chat_bubble_outline,
                  size: 20,
                  color: ShodashaTheme.surface,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Shodasha support',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: ShodashaTheme.surface,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Order, delivery or jar help — message us on WhatsApp.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: ShodashaTheme.tealTint,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            phone,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: ShodashaTheme.surface,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onWhatsApp,
              style: FilledButton.styleFrom(
                backgroundColor: ShodashaTheme.surface,
                foregroundColor: ShodashaTheme.teal,
                minimumSize: const Size.fromHeight(ShodashaTheme.minTarget),
                shape: ShodashaTheme.shape,
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('Chat on WhatsApp'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: ShodashaTheme.muted,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

/// One FAQ row: 48dp tap target, inline expand/collapse, no extra deps.
class _Faq extends StatefulWidget {
  const _Faq({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  State<_Faq> createState() => _FaqState();
}

class _FaqState extends State<_Faq> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Column(
        children: [
          Semantics(
            button: true,
            expanded: _open,
            child: InkWell(
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
              onTap: () => setState(() => _open = !_open),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: ShodashaTheme.minTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.question,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: ShodashaTheme.ink,
                          ),
                        ),
                      ),
                      Icon(
                        _open
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: ShodashaTheme.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.answer,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: ShodashaTheme.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ComplaintEntryCard extends StatelessWidget {
  const _ComplaintEntryCard({required this.onNewComplaint});

  final VoidCallback onNewComplaint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ShodashaTheme.tealTint,
              borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
            ),
            child: const Icon(
              Icons.report_outlined,
              size: 20,
              color: ShodashaTheme.teal,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Raise a complaint',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: ShodashaTheme.ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Tell us what went wrong with an order.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: ShodashaTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onNewComplaint,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(64, ShodashaTheme.minTarget),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: const Text(
              'New',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComplaintsSection extends StatelessWidget {
  const _ComplaintsSection({required this.controller});

  final SupportController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.status == ComplaintStatus.loading &&
        controller.items.isEmpty) {
      return const _ComplaintsSkeleton();
    }
    if (controller.status == ComplaintStatus.error &&
        controller.items.isEmpty) {
      return _ComplaintsError(
        message: controller.errorMessage ?? supportStrings['loadError']!,
        onRetry: controller.load,
      );
    }
    if (controller.items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ShodashaTheme.surface,
          border: Border.all(color: ShodashaTheme.border),
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 18,
              color: ShodashaTheme.muted,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'No complaints yet. If an order goes wrong, raise one above.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: ShodashaTheme.muted,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final complaint in controller.items)
          _ComplaintCard(complaint: complaint),
      ],
    );
  }
}

class _ComplaintCard extends StatelessWidget {
  const _ComplaintCard({required this.complaint});

  final ComplaintEntry complaint;

  (String, Color, Color) get _statusStyle => switch (complaint.status) {
    'resolved' => ('Resolved', ShodashaTheme.muted, ShodashaTheme.bg),
    'progress' || 'in_progress' => (
      'In review',
      ShodashaTheme.onSolar,
      ShodashaTheme.solarTint,
    ),
    _ => ('Open', ShodashaTheme.teal, ShodashaTheme.tealTint),
  };

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor, statusBackground) = _statusStyle;
    final reason =
        kComplaintReasonLabels[complaint.reasonCode] ?? complaint.reasonCode;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reason,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ShodashaTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '#${complaint.orderId}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: ShodashaTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          if (complaint.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              complaint.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: ShodashaTheme.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ComplaintsSkeleton extends StatelessWidget {
  const _ComplaintsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading complaints',
      child: Column(
        children: [
          for (var i = 0; i < 2; i++)
            Container(
              height: 64,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: ShodashaTheme.tealTint,
                borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
              ),
            ),
        ],
      ),
    );
  }
}

class _ComplaintsError extends StatelessWidget {
  const _ComplaintsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            size: 18,
            color: ShodashaTheme.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: ShodashaTheme.muted,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: ShodashaTheme.teal),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

class _ComplaintFormSheet extends StatefulWidget {
  const _ComplaintFormSheet({
    required this.controller,
    required this.onWhatsApp,
  });

  final SupportController controller;
  final Future<void> Function() onWhatsApp;

  @override
  State<_ComplaintFormSheet> createState() => _ComplaintFormSheetState();
}

class _ComplaintFormSheetState extends State<_ComplaintFormSheet> {
  final _orderCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  String _reason = 'water_quality';
  bool _touched = false;
  bool _sending = false;

  bool get _textOk {
    final length = _textCtrl.text.trim().length;
    return length >= 10 && length <= 500;
  }

  bool get _orderOk => _orderCtrl.text.trim().isNotEmpty;
  bool get _valid => _textOk && _orderOk;

  @override
  void dispose() {
    _orderCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _touched = true);
    if (!_valid || _sending) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    final error = await widget.controller.submit(
      orderId: _orderCtrl.text.trim(),
      reasonCode: _reason,
      text: _textCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (error == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Complaint submitted.')));
      return;
    }
    if (error == 'windowExpired') {
      final openWhatsApp = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: ShodashaTheme.shape,
          title: const Text(
            'Complaint window closed',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: const Text(
            'The complaint window for this order has closed. Message us on '
            'WhatsApp and we will help.',
            style: TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: TextButton.styleFrom(foregroundColor: ShodashaTheme.muted),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: ShodashaTheme.teal),
              child: const Text('WhatsApp us'),
            ),
          ],
        ),
      );
      if (openWhatsApp == true && mounted) {
        Navigator.of(context).pop();
        unawaited(widget.onWhatsApp());
      }
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(supportStrings[error] ?? supportStrings['sendError']!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SheetHandle(),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'New complaint',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: ShodashaTheme.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _sending
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: ShodashaTheme.muted),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Share the order and what happened. We review every complaint.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: ShodashaTheme.muted,
              ),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(
                labelText: 'Reason',
                prefixIcon: Icon(Icons.tune),
              ),
              items: [
                for (final entry in kComplaintReasonLabels.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) => setState(() => _reason = value ?? _reason),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('complaint-order'),
              controller: _orderCtrl,
              enabled: !_sending,
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontSize: 16, color: ShodashaTheme.ink),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Order ID',
                hintText: 'A3F9',
                prefixIcon: Icon(Icons.receipt_long_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('complaint-text'),
              controller: _textCtrl,
              enabled: !_sending,
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
              style: const TextStyle(fontSize: 16, color: ShodashaTheme.ink),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'What happened?',
                helperText: '10–500 characters',
                counterText: '',
                alignLabelWithHint: true,
                errorText: _touched && !_textOk
                    ? 'Write at least 10 characters.'
                    : null,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('complaint-submit'),
                onPressed: (_sending || !_valid) ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: ShodashaTheme.teal,
                  foregroundColor: ShodashaTheme.surface,
                  disabledBackgroundColor: ShodashaTheme.teal.withValues(
                    alpha: 0.4,
                  ),
                  minimumSize: const Size.fromHeight(52),
                  shape: ShodashaTheme.shape,
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: _sending
                    ? const Text('Sending…')
                    : const Text('Send complaint'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared sheet drag handle (donor checkout chrome, no image assets).
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: ShodashaTheme.border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
