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
    final estimate = res['first_cycle_estimate'];
    final total = estimate is Map ? (estimate['total'] as num?)?.toInt() : null;
    _showMessage(
      total == null
          ? subStrings['planStarted']!
          : '${subStrings['planStarted']} First delivery estimate '
                '${rupeesLabel(total)} — billed as usual.',
    );
    await _controller.load();
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
                      onPause: () => _pauseSheet(sub),
                      onResume: () => _resumeSheet(sub),
                      onSkip: () => _skipToday(sub),
                      onCancel: () => _cancelSheet(sub),
                    ),
                    const SizedBox(height: 10),
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
class _SubsSkeleton extends StatelessWidget {
  const _SubsSkeleton();

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    itemCount: 3,
    separatorBuilder: (_, _) => const SizedBox(height: 12),
    itemBuilder: (_, _) => Container(
      height: 88,
      decoration: BoxDecoration(
        color: ShodashaTheme.tealTint,
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 64),
      const Icon(
        Icons.cloud_off_outlined,
        size: 40,
        color: ShodashaTheme.muted,
      ),
      const SizedBox(height: 12),
      Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: ShodashaTheme.ink,
        ),
      ),
      const SizedBox(height: 16),
      Center(
        child: OutlinedButton(
          onPressed: onRetry,
          child: Text(subStrings['retry']!),
        ),
      ),
    ],
  );
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
    decoration: BoxDecoration(
      color: ShodashaTheme.solarTint,
      border: Border.all(color: ShodashaTheme.solarBorder),
      borderRadius: BorderRadius.circular(ShodashaTheme.radius),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.warning_amber_outlined,
          size: 16,
          color: ShodashaTheme.solarDark,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            subStrings['refreshFailed']!,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ShodashaTheme.onSolar,
            ),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(foregroundColor: ShodashaTheme.teal),
          child: Text(subStrings['retry']!),
        ),
      ],
    ),
  );
}

/// Dues are server-owned (`GET /billing/dues`); paying creates one idempotent
/// `POST /payments/dues-intent` and opens the returned UPI deep link.
class _DuesStrip extends StatelessWidget {
  const _DuesStrip({
    required this.duesPaise,
    required this.busy,
    required this.onPay,
    this.onOpenWallet,
  });

  final int duesPaise;
  final bool busy;
  final VoidCallback onPay;
  final VoidCallback? onOpenWallet;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: ShodashaTheme.tealTint,
      border: Border.all(color: ShodashaTheme.teal.withValues(alpha: 0.25)),
      borderRadius: BorderRadius.circular(ShodashaTheme.radius),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.account_balance_wallet_outlined,
          size: 20,
          color: ShodashaTheme.teal,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subStrings['duesTitle']!,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: ShodashaTheme.tealDeep,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                rupeesLabel(duesPaise),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: ShodashaTheme.ink,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AppButton(
              label: subStrings['payDues']!,
              kind: AppButtonKind.money,
              expand: false,
              height: ShodashaTheme.minTarget,
              onPressed: busy ? null : onPay,
            ),
            if (onOpenWallet != null)
              TextButton(
                onPressed: onOpenWallet,
                style: TextButton.styleFrom(
                  foregroundColor: ShodashaTheme.blue,
                ),
                child: Text(
                  subStrings['wallet']!,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onBuild});

  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: ShodashaTheme.surface,
      border: Border.all(color: ShodashaTheme.border),
      borderRadius: BorderRadius.circular(ShodashaTheme.radius),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: ShodashaTheme.tealTint,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.event_repeat, color: ShodashaTheme.teal),
        ),
        const SizedBox(height: 12),
        Text(
          subStrings['emptyTitle']!,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
            color: ShodashaTheme.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subStrings['emptyHint']!,
          style: const TextStyle(
            fontSize: 13,
            height: 1.35,
            color: ShodashaTheme.muted,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            // Plan creation is not a charge — teal, never money green.
            style: ElevatedButton.styleFrom(
              backgroundColor: ShodashaTheme.teal,
              foregroundColor: ShodashaTheme.surface,
            ),
            onPressed: onBuild,
            icon: const Icon(Icons.add),
            label: Text(subStrings['buildPlan']!),
          ),
        ),
      ],
    ),
  );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.sub,
    required this.busy,
    required this.onPause,
    required this.onResume,
    required this.onSkip,
    required this.onCancel,
  });

  final SubscriptionEntry sub;
  final bool busy;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onSkip;
  final VoidCallback onCancel;

  String get _skuLabel =>
      sub.skuMix == 'container' ? '20L jar + container' : '20L refill jar';

  @override
  Widget build(BuildContext context) {
    final next = sub.nextRun;
    final holdTo = sub.holdTo;
    final due = sub.dueTodayPaise;
    final monthly = sub.monthlyEstimatePaise;
    return Container(
      padding: const EdgeInsets.all(14),
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
              Expanded(
                child: Text(
                  sub.addressLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: ShodashaTheme.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(sub: sub),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            sub.qty > 0 ? '${sub.qty} × $_skuLabel' : _skuLabel,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ShodashaTheme.muted,
            ),
          ),
          if (sub.window.isNotEmpty)
            Text(
              '${subStrings['windowLabel']}: ${sub.window}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ShodashaTheme.muted,
              ),
            ),
          if (!sub.paused && !sub.canceled && next != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.schedule, size: 14, color: ShodashaTheme.teal),
                const SizedBox(width: 6),
                Text(
                  '${subStrings['nextRun']}: $next',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.teal,
                  ),
                ),
              ],
            ),
          ],
          if (sub.paused && holdTo != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${subStrings['pausedUntil']} $holdTo',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ShodashaTheme.muted,
                ),
              ),
            ),
          if (sub.canceled)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subStrings['canceledNote']!,
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: ShodashaTheme.muted,
                ),
              ),
            ),
          if (!sub.canceled) ...[
            if (due != null && due > 0) ...[
              const SizedBox(height: 6),
              _MoneyRow(label: subStrings['dueToday']!, paise: due),
            ],
            if (monthly != null && monthly > 0)
              _MoneyRow(
                label: subStrings['monthlyEstimate']!,
                paise: monthly,
                soft: true,
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [
                if (sub.paused)
                  TextButton(
                    onPressed: busy ? null : onResume,
                    style: TextButton.styleFrom(
                      foregroundColor: ShodashaTheme.teal,
                    ),
                    child: Text(subStrings['resume']!),
                  )
                else
                  TextButton(
                    onPressed: busy ? null : onPause,
                    style: TextButton.styleFrom(
                      foregroundColor: ShodashaTheme.teal,
                    ),
                    child: Text(subStrings['pause']!),
                  ),
                if (!sub.paused)
                  TextButton(
                    onPressed: busy ? null : onSkip,
                    style: TextButton.styleFrom(
                      foregroundColor: ShodashaTheme.teal,
                    ),
                    child: Text(subStrings['skipToday']!),
                  ),
                TextButton(
                  onPressed: busy ? null : onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: ShodashaTheme.danger,
                  ),
                  child: Text(subStrings['cancel']!),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.sub});

  final SubscriptionEntry sub;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = sub.canceled
        ? (subStrings['canceled']!, ShodashaTheme.danger, ShodashaTheme.bg)
        : sub.paused
        ? (subStrings['paused']!, ShodashaTheme.muted, ShodashaTheme.bg)
        : (subStrings['active']!, ShodashaTheme.teal, ShodashaTheme.tealTint);
    return Semantics(
      label: 'Status: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
            color: fg,
          ),
        ),
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.paise,
    this.soft = false,
  });

  final String label;
  final int paise;
  final bool soft;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ShodashaTheme.muted,
          ),
        ),
        Text(
          rupeesLabel(paise),
          style: TextStyle(
            fontSize: soft ? 12 : 14,
            fontWeight: soft ? FontWeight.w700 : FontWeight.w800,
            color: ShodashaTheme.ink,
          ),
        ),
      ],
    ),
  );
}

/// Pause range picker (end must be after start — legacy validation).
class _PauseSheet extends StatefulWidget {
  const _PauseSheet();

  @override
  State<_PauseSheet> createState() => _PauseSheetState();
}

class _PauseSheetState extends State<_PauseSheet> {
  late DateTime _from;
  late DateTime _to;
  String? _error;

  @override
  void initState() {
    super.initState();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _from = tomorrow;
    _to = tomorrow.add(const Duration(days: 7));
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
      _error = null;
    });
  }

  void _confirm() {
    if (_to.compareTo(_from) <= 0) {
      setState(() => _error = subStrings['errRange']);
      return;
    }
    Navigator.of(
      context,
    ).pop('${ApiClient.dateOnly(_from)}|${ApiClient.dateOnly(_to)}');
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      16,
      16,
      16 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          subStrings['pauseTitle']!,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: ShodashaTheme.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subStrings['pauseBody']!,
          style: const TextStyle(
            fontSize: 13,
            height: 1.35,
            color: ShodashaTheme.muted,
          ),
        ),
        const SizedBox(height: 16),
        _dateRow(
          label: subStrings['fromDate']!,
          date: _from,
          onTap: () => _pickDate(isFrom: true),
        ),
        const SizedBox(height: 8),
        _dateRow(
          label: subStrings['toDate']!,
          date: _to,
          onTap: () => _pickDate(isFrom: false),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ShodashaTheme.danger,
              ),
            ),
          ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            // Plan management → teal (never the money green).
            style: ElevatedButton.styleFrom(
              backgroundColor: ShodashaTheme.teal,
              foregroundColor: ShodashaTheme.surface,
            ),
            onPressed: _confirm,
            child: Text(subStrings['pauseConfirm']!),
          ),
        ),
      ],
    ),
  );

  Widget _dateRow({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ShodashaTheme.ink,
          ),
        ),
      ),
      OutlinedButton(onPressed: onTap, child: Text(ApiClient.dateOnly(date))),
    ],
  );
}

/// Cancellation reason + refund destination; the server computes refunds.
class _CancelSheet extends StatefulWidget {
  const _CancelSheet();

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  final _upi = TextEditingController();
  bool _touched = false;
  String _reason = 'I don\'t need jars anymore';

  bool get _upiOk =>
      RegExp(r'^[A-Za-z0-9._-]{2,}@[A-Za-z]{2,}$').hasMatch(_upi.text.trim());

  void _confirm() {
    setState(() => _touched = true);
    if (!_upiOk) return;
    Navigator.of(context).pop({'reason': _reason, 'upi_id': _upi.text.trim()});
  }

  static const List<String> _reasons = [
    "I don't need jars anymore",
    'Moving to another city or area',
    "Delivery time doesn't suit me",
    'Quality or service issue',
    'Something else',
  ];

  @override
  void dispose() {
    _upi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      12,
      16,
      16 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cancel_outlined,
                color: ShodashaTheme.danger,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subStrings['cancelTitle']!,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: ShodashaTheme.ink,
                  ),
                ),
              ),
              IconButton(
                tooltip: subStrings['close'],
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ShodashaTheme.bg,
              border: Border.all(color: ShodashaTheme.border),
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            ),
            child: Text(
              subStrings['cancelBody']!,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: ShodashaTheme.muted,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            subStrings['cancelReason']!,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ShodashaTheme.ink,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _reason,
            isExpanded: true,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            items: [
              for (final reason in _reasons)
                DropdownMenuItem(
                  value: reason,
                  child: Text(
                    reason,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _reason = value);
            },
          ),
          const SizedBox(height: 14),
          Text(
            subStrings['cancelUpi']!,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ShodashaTheme.ink,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _upi,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'e.g. 9876543210@upi',
              helperText: 'Refund is sent to this UPI ID after pickup.',
              errorText: _touched && !_upiOk
                  ? 'Enter a valid UPI ID, like 9876543210@upi.'
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 18),
          AppButton(
            label: subStrings['cancelConfirm']!,
            kind: AppButtonKind.danger,
            onPressed: _confirm,
          ),
        ],
      ),
    ),
  );
}
