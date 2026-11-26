// S6 — Subscriptions tab: list + due strip + pause/resume/skip/cancel.
//
// Ported from apps/user_app_legacy_flutter/features/subscriptions with the
// donor card/pill grammar (white plan cards on the slate ground, real status
// pills only) and the v1 money laws:
//   • every amount comes from `GET /subscriptions`, `GET /billing/dues`, or
//     `POST /subscriptions/estimate` — no client math, no fake Rs 0;
//   • green only on the dues money CTA; plan management is teal;
//   • status is never invented: Canceled wins over Paused, Active otherwise.
// Dues payment itself is the Wallet slice (S7): the strip routes through
// [SubscriptionScreen.onOpenWallet] instead of posting an intent here.
// States.md: skeleton → empty (teaches the plan builder) → error + retry;
// stale list with a refresh warning; every mutation pending/success/failure.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui/app_button.dart';
import '../../shared/ui/app_icon_button.dart';
import 'plan_builder_sheet.dart';
import 'subscription_controller.dart';

part 'widgets/subscription_cards.dart';
part 'widgets/subscription_sheets.dart';

/// Subscriptions tab body. Shell wiring: pass the ONE authenticated
/// [ApiClient] (ADR-112) and, optionally, a callback that switches the shell
/// to the Wallet tab for dues payment.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({
    super.key,
    required this.api,
    this.onOpenWallet,
    this.onSignIn,
    this.onAddAddress,
  });

  final ApiClient api;

  /// Nullable cross-feature seam (hard law: no cross-feature imports).
  final VoidCallback? onOpenWallet;
  final VoidCallback? onSignIn;
  final VoidCallback? onAddAddress;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late final SubscriptionController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SubscriptionController(api: widget.api);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.load();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _copy(String keyOrText) => subStrings[keyOrText] ?? keyOrText;

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openBuilder() async {
    if (!widget.api.hasToken) {
      _showMessage(subStrings['signedOutPlan']!);
      return;
    }
    final res = await showPlanBuilderSheet(
      context,
      api: widget.api,
      onSignIn: widget.onSignIn,
      onAddAddress: widget.onAddAddress,
    );
    if (res == null || !mounted) return;
    await _controller.load();
    if (!mounted) return;
    // Doorstep Cash on Delivery (COD) activation — bypass external gateway redirect (Point 4)
    final estimate = res['first_cycle_estimate'];
    final total = estimate is Map ? (estimate['total'] as num?)?.toInt() : null;
    _showMessage(
      total == null
          ? subStrings['planStarted']!
          : '${subStrings['planStarted']} First delivery estimate '
                '${rupeesLabel(total)} — billed as usual.',
    );
  }

  /// One prepaid top-up: server intent → UPI app → poll the plan until the
  /// webhook confirms. Never claims active while billing_status is pending.
  Future<void> _startTopUp(String subId) async {
    final res = await _controller.topUp(subId);
    if (!mounted || res == null) return;
    if (res.containsKey('error')) {
      _showMessage(res['error'].toString());
      return;
    }
    final link = (res['link'] ?? '').toString();
    final ref = (res['provider_ref'] ?? '').toString();
    final charge = res['charge'];
    final amount = charge is Map ? (charge['amount'] as num?)?.toInt() : null;
    if (link.isEmpty) {
      _showMessage(subStrings['topupFailed']!);
      return;
    }
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(link),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }
    if (!mounted) return;
    final active = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TopUpDialog(
        link: link,
        reference: ref,
        amountPaise: amount,
        launched: launched,
        onCheck: () => _controller.confirmTopUp(subId),
      ),
    );
    if (!mounted) return;
    await _controller.load();
    if (!mounted) return;
    _showMessage(
      _copy(active == true ? 'topupConfirmed' : 'planStartedPrepaid'),
    );
  }

  Future<void> _pauseSheet(SubscriptionEntry sub) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ShodashaTheme.radiusSheet),
        ),
      ),
      builder: (_) => const _PauseSheet(),
    );
    if (picked == null || !mounted) return;
    final parts = picked.split('|');
    if (parts.length != 2) return;
    final error = await _controller.pause(sub.id, parts[0], parts[1]);
    if (!mounted) return;
    _showMessage(_copy(error ?? 'saved'));
  }

  Future<void> _resumeSheet(SubscriptionEntry sub) async {
    final first = DateTime.now().add(const Duration(days: 2)); // ≥24h guard
    final picked = await showDatePicker(
      context: context,
      initialDate: first,
      firstDate: first,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: subStrings['resumeNote'],
    );
    if (picked == null || !mounted) return;
    final error = await _controller.resume(sub.id, ApiClient.dateOnly(picked));
    if (!mounted) return;
    _showMessage(_copy(error ?? 'saved'));
  }

  Future<void> _skipToday(SubscriptionEntry sub) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: ShodashaTheme.shape,
        title: Text(subStrings['skipConfirmTitle']!),
        content: Text(subStrings['skipConfirmBody']!),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(foregroundColor: ShodashaTheme.muted),
            child: Text(subStrings['skipKeep']!),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(subStrings['skipConfirm']!),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final error = await _controller.skipToday(sub.id);
    if (!mounted) return;
    if (error == 'lateSkip') {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: ShodashaTheme.shape,
          title: Text(subStrings['lateSkipTitle']!),
          content: Text(
            '${subStrings['lateSkipBody']}$kSupportPhone'
            '${subStrings['lateSkipTail']}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: TextButton.styleFrom(foregroundColor: ShodashaTheme.teal),
              child: Text(subStrings['ok']!),
            ),
          ],
        ),
      );
      return;
    }
    _showMessage(_copy(error ?? 'saved'));
  }

  /// Full dues → one idempotent UPI intent. The returned deep link is opened in
  /// the user's UPI app; the webhook remains the only settlement truth. If the
  /// launch fails the dialog still offers Copy link and Wallet, never a dead
  /// end.
  Future<void> _payDues() async {
    final res = await _controller.payDues();
    if (!mounted || res == null) return;
    if (res.containsKey('error')) {
      _showMessage(res['error'].toString());
      return;
    }
    final ref = (res['provider_ref'] ?? '').toString();
    final link = (res['link'] ?? res['upi_link'] ?? '').toString();
    if (link.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: ShodashaTheme.shape,
          title: const Text('Payment link unavailable'),
          content: const Text(
            'No payment was collected. Open Wallet to review your dues, or '
            'call support if this keeps happening.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            if (widget.onOpenWallet != null)
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  widget.onOpenWallet!();
                },
                style: TextButton.styleFrom(
                  foregroundColor: ShodashaTheme.blue,
                ),
                child: Text(subStrings['wallet']!),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: TextButton.styleFrom(foregroundColor: ShodashaTheme.teal),
              child: Text(subStrings['ok']!),
            ),
          ],
        ),
      );
      return;
    }

    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(link),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: ShodashaTheme.shape,
        title: Text(
          launched ? subStrings['duesPayTitle']! : 'Payment link ready',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              launched
                  ? subStrings['duesPayBody']!
                  : 'Your UPI app did not open. Copy the link and pay in any '
                        'UPI app — dues clear after the provider confirms.',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            if (ref.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${subStrings['duesPayRef']}: $ref',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ShodashaTheme.muted,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              messenger.showSnackBar(
                const SnackBar(content: Text('Payment link copied.')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: ShodashaTheme.blue),
            child: const Text('Copy link'),
          ),
          if (widget.onOpenWallet != null)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                widget.onOpenWallet!();
              },
              style: TextButton.styleFrom(foregroundColor: ShodashaTheme.blue),
              child: Text(subStrings['wallet']!),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(foregroundColor: ShodashaTheme.teal),
            child: Text(subStrings['ok']!),
          ),
        ],
      ),
    );
    // Pick up a fast webhook; if it has not landed the strip stays honest.
    if (mounted) await _controller.load();
  }

  Future<void> _cancelSheet(SubscriptionEntry sub) async {
    final picked = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ShodashaTheme.radiusSheet),
        ),
      ),
      builder: (_) => const _CancelSheet(),
    );
    if (picked == null || !mounted) return;
    final outcome = await _controller.cancelSubscription(
      sub.id,
      picked['reason'] ?? '',
      picked['upi_id'] ?? '',
    );
    if (!mounted) return;
    if (outcome == null) {
      _showMessage(subStrings['loadFailed']!);
      return;
    }
    if (outcome.containsKey('error')) {
      _showMessage(outcome['error'].toString());
      return;
    }
    final message = (outcome['message'] ?? '').toString();
    final water = (outcome['unused_water_refund_paise'] as num?)?.toInt();
    final jars = (outcome['jars_to_return'] as num?)?.toInt();
    final deposit = (outcome['deposit_refund_expected_paise'] as num?)?.toInt();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: ShodashaTheme.shape,
        title: Text(subStrings['cancelDone']!),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.isNotEmpty ? message : subStrings['cancelDoneBody']!,
              style: const TextStyle(fontSize: 13),
            ),
            if ((water == null || water <= 0) &&
                (jars == null || jars <= 0)) ...[
              const SizedBox(height: 8),
              Text(
                subStrings['cancelNoRefund']!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ShodashaTheme.ink,
                ),
              ),
            ],
            if (water != null && water > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Unused water refund: ${rupeesLabel(water)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ShodashaTheme.ink,
                ),
              ),
            ],
            if (jars != null && jars > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Jars to pick up: $jars',
                style: const TextStyle(fontSize: 13),
              ),
            ],
            if (deposit != null && deposit > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Deposit refund expected: ${rupeesLabel(deposit)}',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(foregroundColor: ShodashaTheme.teal),
            child: Text(subStrings['ok']!),
          ),
        ],
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
        title: Text(
          subStrings['title']!,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: ShodashaTheme.ink,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => AppIconButton(
              icon: Icons.refresh_rounded,
              tooltip: subStrings['refresh']!,
              onPressed: _controller.busy ? null : _controller.load,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final c = _controller;
          if (c.status == SubStatus.loading && c.items.isEmpty) {
            return const _SubsSkeleton();
          }
          if (c.status == SubStatus.error && c.items.isEmpty) {
            return _ErrorState(
              message: c.errorMessage ?? subStrings['loadFailed']!,
              onRetry: c.load,
            );
          }
          return RefreshIndicator(
            onRefresh: c.load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (c.busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: ShodashaTheme.teal,
                      backgroundColor: ShodashaTheme.tealTint,
                    ),
                  ),
                if (c.status == SubStatus.error && c.items.isNotEmpty) ...[
                  _StaleBanner(onRetry: c.load),
                  const SizedBox(height: 12),
                ],
                if (c.duesPaise != null) ...[
                  _DuesStrip(
                    duesPaise: c.duesPaise!,
                    busy: c.busy,
                    onPay: _payDues,
                    onOpenWallet: widget.onOpenWallet,
                  ),
                  const SizedBox(height: 12),
                ],
                if (c.items.isEmpty)
                  _EmptyState(onBuild: _openBuilder)
                else ...[
                  for (final sub in c.items) ...[
                    _PlanCard(
                      sub: sub,
                      busy: c.busy,
                      onTopUp: () => _startTopUp(sub.id),
                      onPause: () => _pauseSheet(sub),
                      onResume: () => _resumeSheet(sub),
                      onSkip: () => _skipToday(sub),
                      onCancel: () => _cancelSheet(sub),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  OutlinedButton.icon(
                    onPressed: c.busy ? null : _openBuilder,
                    icon: const Icon(Icons.add),
                    label: Text(subStrings['buildPlan']!),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// First-load skeleton (legacy Phase 9 rhythm — no bare spinner).
