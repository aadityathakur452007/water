part of '../subscription_screen.dart';

class _SubsSkeleton extends StatelessWidget {
  const _SubsSkeleton();

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    itemCount: 3,
    separatorBuilder: (_, _) => const SizedBox(height: 12),
    itemBuilder: (_, _) => Container(
      height: 96,
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 14,
            width: 140,
            decoration: BoxDecoration(
              color: ShodashaTheme.skeleton,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            height: 12,
            width: 220,
            decoration: BoxDecoration(
              color: ShodashaTheme.skeleton,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
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
        AppButton(
          label: subStrings['buildPlan']!,
          kind: AppButtonKind.primary,
          icon: Icons.add,
          onPressed: onBuild,
        ),
      ],
    ),
  );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.sub,
    required this.busy,
    required this.onTopUp,
    required this.onPause,
    required this.onResume,
    required this.onSkip,
    required this.onCancel,
  });

  final SubscriptionEntry sub;
  final bool busy;
  final VoidCallback onTopUp;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onSkip;
  final VoidCallback onCancel;

  String get _skuLabel =>
      sub.skuMix == 'container' ? '20L jar + container' : '20L refill jar';

  String get _billingLabel => switch (sub.billingMode) {
    'monthly_prepaid' => subStrings['billingPrepaid']!,
    'monthly_postpaid' => subStrings['billingPostpaid']!,
    _ => subStrings['billingPerDelivery']!,
  };

  String get _paymentLabel => sub.paymentMethod == 'upi'
      ? subStrings['paymentUpi']!
      : subStrings['paymentCod']!;

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
          _DetailRow(label: subStrings['billing']!, value: _billingLabel),
          _DetailRow(label: subStrings['payment']!, value: _paymentLabel),
          if (sub.lifecycle == SubscriptionLifecycle.active && next != null) ...[
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
          if (sub.todayDeliveryOtp != null && sub.todayDeliveryOtp!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: ShodashaTheme.tealTint,
                borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                border: Border.all(color: ShodashaTheme.teal),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.pin_rounded, size: 16, color: ShodashaTheme.tealDeep),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          "TODAY'S DELIVERY OTP",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: ShodashaTheme.tealDeep,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (sub.todayOrderState != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: ShodashaTheme.surface,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            sub.todayOrderState!.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: ShodashaTheme.teal,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sub.todayDeliveryOtp!,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: ShodashaTheme.tealDeep,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Share this 4-digit OTP with the delivery partner at your doorstep.',
                    style: TextStyle(fontSize: 11, color: ShodashaTheme.ink),
                  ),
                ],
              ),
            ),
          ],
          if (sub.paused)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Builder(
                builder: (_) {
                  final parsedHoldTo = DateTime.tryParse(sub.holdTo ?? '');
                  final isIndefinite = parsedHoldTo != null &&
                      parsedHoldTo.difference(DateTime.now()).inDays > 180;
                  final text = isIndefinite
                      ? 'Paused indefinitely (tap Resume anytime)'
                      : (holdTo != null ? '${subStrings['pausedUntil']} $holdTo' : 'Paused');
                  return Text(
                    text,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ShodashaTheme.muted,
                    ),
                  );
                },
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
          if (!sub.canceled && sub.isPrepaid) ...[
            const SizedBox(height: 6),
            _MoneyRow(
              label: subStrings['prepaidBalance']!,
              paise: sub.creditBalancePaise,
            ),
          ],
          if (!sub.canceled && sub.lowBalance) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ShodashaTheme.solarTint,
                border: Border.all(color: ShodashaTheme.solarBorder),
                borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 16,
                    color: ShodashaTheme.solarDark,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      subStrings['lowBalance']!,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: ShodashaTheme.onSolar,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1, color: ShodashaTheme.border),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                if (sub.isPrepaid)
                  TextButton.icon(
                    onPressed: busy ? null : onTopUp,
                    style: TextButton.styleFrom(
                      foregroundColor: ShodashaTheme.blue,
                    ),
                    icon: const Icon(Icons.add_card, size: 16),
                    label: Text(subStrings['addTopUp']!),
                  ),
                if (sub.lifecycle == SubscriptionLifecycle.paused)
                  TextButton(
                    onPressed: busy ? null : onResume,
                    style: TextButton.styleFrom(
                      foregroundColor: ShodashaTheme.teal,
                    ),
                    child: Text(subStrings['resume']!),
                  )
                else if (sub.lifecycle == SubscriptionLifecycle.active)
                  TextButton(
                    onPressed: busy ? null : onPause,
                    style: TextButton.styleFrom(
                      foregroundColor: ShodashaTheme.teal,
                    ),
                    child: Text(subStrings['pause']!),
                  ),
                if (sub.lifecycle == SubscriptionLifecycle.active)
                  TextButton(
                    onPressed: busy ? null : onSkip,
                    style: TextButton.styleFrom(
                      foregroundColor: ShodashaTheme.teal,
                    ),
                    child: Text(subStrings['skipToday']!),
                  ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: 'More options',
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: ShodashaTheme.muted,
                    size: 20,
                  ),
                  onSelected: (value) {
                    if (value == 'cancel' && !busy) onCancel();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'cancel',
                      child: Row(
                        children: [
                          const Icon(
                            Icons.cancel_outlined,
                            size: 18,
                            color: ShodashaTheme.danger,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            subStrings['cancel']!,
                            style: const TextStyle(
                              color: ShodashaTheme.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
    final (label, fg, bg) = switch (sub.lifecycle) {
      SubscriptionLifecycle.canceled => (
        subStrings['canceled']!,
        ShodashaTheme.danger,
        ShodashaTheme.bg,
      ),
      SubscriptionLifecycle.paused => (
        subStrings['paused']!,
        ShodashaTheme.muted,
        ShodashaTheme.bg,
      ),
      SubscriptionLifecycle.awaitingPayment => (
        subStrings['billingPending']!,
        ShodashaTheme.solarDark,
        ShodashaTheme.solarTint,
      ),
      SubscriptionLifecycle.lowBalance => (
        subStrings['lowBalanceStatus']!,
        ShodashaTheme.solarDark,
        ShodashaTheme.solarTint,
      ),
      SubscriptionLifecycle.active => (
        subStrings['active']!,
        ShodashaTheme.teal,
        ShodashaTheme.tealTint,
      ),
    };
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
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
            color: fg,
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ShodashaTheme.muted,
          ),
        ),
        Text(
          value,
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
