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
import '../../shared/ui/app_banner.dart';
import '../../shared/ui/app_button.dart';
import '../../shared/ui/app_icon_button.dart';
import 'support_controller.dart';

String _supportDate(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final d = value.toLocal();
  return '${d.day} ${months[d.month - 1]}';
}

/// A delivered order the complaint form can point at. The shell maps the
/// OrdersController rows into this tiny shape so Support does not reach into
/// another feature's state.
@immutable
class SupportOrder {
  const SupportOrder({required this.id, required this.label, this.deliveredAt});

  final String id;
  final String label;
  final DateTime? deliveredAt;
}

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
    this.orders = const [],
  });

  /// Authenticated transport from the shell — complaints carry the real
  /// Bearer and persisted X-Device-Id.
  final ApiClient api;

  final SupportController? controller;

  /// Prefilled WhatsApp text when opened from an order (contextual help).
  final String? orderContext;

  /// Injectable for widget tests (defaults to url_launcher's external app).
  final Future<bool> Function(Uri url, {LaunchMode mode})? openUrl;

  /// Delivered orders offered as the primary complaint target.
  final List<SupportOrder> orders;

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

  Future<void> _openCall() async {
    final open = widget.openUrl ?? launchUrl;
    bool ok = false;
    try {
      ok = await open(
        Uri(scheme: 'tel', path: kSupportPhone),
        mode: LaunchMode.externalApplication,
      );
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
      const SnackBar(content: Text('Call did not open — number copied.')),
    );
  }

  Future<void> _openComplaintForm() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: ShodashaTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ShodashaTheme.radiusSheet),
        ),
      ),
      builder: (_) => _ComplaintFormSheet(
        controller: _controller,
        onWhatsApp: _openWhatsApp,
        onCall: _openCall,
        orders: widget.orders,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShodashaTheme.bg,
      appBar: AppBar(
        backgroundColor: ShodashaTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: ShodashaTheme.border)),
        leadingWidth: 56,
        leading: AppIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Help & support',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: ShodashaTheme.ink,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: ShodashaTheme.tealDeep,
        onRefresh: _controller.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: [
            _HelplineCard(
              phone: kSupportPhone,
              onWhatsApp: _openWhatsApp,
              onCall: _openCall,
            ),
            const _SectionLabel('Common questions'),
            for (final faq in _faqs)
              _Faq(question: faq.question, answer: faq.answer),
            const _SectionLabel('Complaints'),
            _ComplaintEntryCard(onNewComplaint: _openComplaintForm),
            const SizedBox(height: AppSpacing.xl),
            const Text(
              'Your complaints',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: ShodashaTheme.ink,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) =>
                  _ComplaintsSection(controller: _controller),
            ),
          ],
        ),
      ),
    );
  }
}

/// Solid teal helpline banner (donor grammar, gradient flattened). The
/// WhatsApp action is white-on-teal — green stays reserved for money CTAs.
class _HelplineCard extends StatelessWidget {
  const _HelplineCard({
    required this.phone,
    required this.onWhatsApp,
    required this.onCall,
  });

  final String phone;
  final VoidCallback onWhatsApp;
  final VoidCallback onCall;

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
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'WhatsApp',
                  kind: AppButtonKind.secondary,
                  icon: Icons.chat_bubble_outline,
                  height: 48,
                  onPressed: onWhatsApp,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: onCall,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ShodashaTheme.surface,
                      side: const BorderSide(color: ShodashaTheme.surface),
                      shape: ShodashaTheme.shape,
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    icon: const Icon(Icons.call_outlined, size: 18),
                    label: const Text('Call'),
                  ),
                ),
              ),
            ],
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
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: ShodashaTheme.muted,
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
        if (controller.status == ComplaintStatus.error) ...[
          AppBanner.stale(
            message: controller.errorMessage ?? supportStrings['loadError']!,
            onRetry: controller.load,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
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
    required this.onCall,
    this.orders = const [],
  });

  final SupportController controller;
  final Future<void> Function() onWhatsApp;
  final Future<void> Function() onCall;
  final List<SupportOrder> orders;

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

  bool get _orderOk =>
      RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(_orderCtrl.text.trim());
  bool get _valid => _textOk && _orderOk;

  SupportOrder? get _selectedOrder {
    final id = _orderCtrl.text.trim();
    for (final order in widget.orders) {
      if (order.id == id) return order;
    }
    return null;
  }

  String get _deadline {
    final base = _reason == 'water_quality'
        ? 'Water-quality complaints can be raised within 24 hours of delivery.'
        : 'General complaints can be raised within 3 days of delivery.';
    final delivered = _selectedOrder?.deliveredAt;
    if (delivered == null) return base;
    final closes = delivered.add(
      Duration(hours: _reason == 'water_quality' ? 24 : 72),
    );
    return '$base This order: ${_supportDate(delivered)} – '
        '${_supportDate(closes)}.';
  }

  Future<void> _copyOrderId() async {
    final id = _orderCtrl.text.trim();
    if (id.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Order ID copied.')));
  }

  @override
  void dispose() {
    _orderCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    setState(() => _touched = true);
    if (!_valid) return;
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
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Complaint submitted.')),
      );
      return;
    }
    if (error == 'windowExpired') {
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: ShodashaTheme.shape,
          title: const Text(
            'Complaint window closed',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'The complaint window for this order has closed. Message or call '
            'us and we will help.',
            style: TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: TextButton.styleFrom(foregroundColor: ShodashaTheme.muted),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('call'),
              style: TextButton.styleFrom(foregroundColor: ShodashaTheme.teal),
              child: const Text('Call'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('whatsapp'),
              style: TextButton.styleFrom(foregroundColor: ShodashaTheme.teal),
              child: const Text('WhatsApp'),
            ),
          ],
        ),
      );
      if (action != null && mounted) {
        Navigator.of(context).pop();
        if (action == 'whatsapp') {
          unawaited(widget.onWhatsApp());
        } else {
          unawaited(widget.onCall());
        }
      }
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(supportStrings[error] ?? error)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_sending,
      child: SafeArea(
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
                  AppIconButton(
                    icon: Icons.close,
                    tooltip: 'Close complaint',
                    color: ShodashaTheme.muted,
                    onPressed: _sending
                        ? null
                        : () => Navigator.of(context).pop(),
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
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _reason = value ?? _reason),
              ),
              const SizedBox(height: 6),
              Text(
                _deadline,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: ShodashaTheme.muted,
                ),
              ),
              const SizedBox(height: 14),
              if (widget.orders.isNotEmpty) ...[
                const Text(
                  'Delivered orders',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.ink,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.orders.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      final order = widget.orders[i];
                      final selected = _orderCtrl.text.trim() == order.id;
                      return ChoiceChip(
                        label: Text(order.label),
                        selected: selected,
                        showCheckmark: false,
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        selectedColor: ShodashaTheme.tealTint,
                        backgroundColor: ShodashaTheme.bg,
                        side: BorderSide(
                          color: selected
                              ? ShodashaTheme.teal
                              : ShodashaTheme.border,
                        ),
                        labelStyle: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? ShodashaTheme.tealDeep
                              : ShodashaTheme.ink,
                        ),
                        onSelected: (_) =>
                            setState(() => _orderCtrl.text = order.id),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                key: const Key('complaint-order'),
                controller: _orderCtrl,
                enabled: !_sending,
                textInputAction: TextInputAction.next,
                style: const TextStyle(fontSize: 16, color: ShodashaTheme.ink),
                onChanged: (_) => setState(() => _touched = true),
                decoration: InputDecoration(
                  labelText: 'Order ID',
                  hintText: '32-character order ID',
                  prefixIcon: const Icon(Icons.receipt_long_outlined),
                  errorText: _touched && !_orderOk
                      ? 'Pick a delivered order or enter its full 32-character ID.'
                      : null,
                  suffixIcon: _orderCtrl.text.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Copy order ID',
                          onPressed: _copyOrderId,
                          icon: const Icon(Icons.copy_rounded, size: 18),
                        ),
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
                onChanged: (_) => setState(() => _touched = true),
                decoration: InputDecoration(
                  labelText: 'What happened?',
                  helperText: '10–500 characters',
                  counterText: '${_textCtrl.text.trim().length}/500',
                  alignLabelWithHint: true,
                  errorText: _touched && !_textOk
                      ? 'Write at least 10 characters.'
                      : null,
                ),
              ),
              const SizedBox(height: 18),
              AppButton(
                key: const Key('complaint-submit'),
                label: 'Send complaint',
                busy: _sending,
                onPressed: _sending ? null : _submit,
              ),
            ],
          ),
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
