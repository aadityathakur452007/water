// S7 — Wallet tab: jar ledger + payments history + returns entry.
//
// Data truth: the hero and every row come from GET /v1/ledger/me through
// [WalletController]. There is no wallet-balance concept and no Add Money —
// our backend has neither. States.md coverage: guest (login CTA, no socket),
// loading (skeleton), loaded (solid-teal hero + statement), empty (all-zero
// server snapshot explained), error (message + retry), pull actions for
// payments and returns. A ₹0 hero is never rendered before the server answers.

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../returns/return_sheet.dart';
import '../returns/returns_controller.dart';
import 'payment_history_screen.dart';
import 'wallet_controller.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({
    super.key,
    required this.api,
    required this.isAuthenticated,
    this.onLoginRequired,
    this.pickAddress,
    this.refreshTick = 0,
  });

  /// The ONE app-wide authenticated client (core/api_client.dart).
  final ApiClient api;

  /// Read at build/init time — the shell stays mounted while auth changes.
  final bool Function() isAuthenticated;

  /// Guest CTA; omitted when the host has no login route yet.
  final VoidCallback? onLoginRequired;

  /// Injected address picker for the returns sheet (nullable — see
  /// [ReturnAddressPicker]). Returns never imports the addresses feature.
  final ReturnAddressPicker? pickAddress;

  /// Bumped by the shell on every Wallet tab entry so a ledger changed
  /// elsewhere (dues paid in Subscriptions, a return filed earlier) reloads.
  final int refreshTick;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  late final WalletController _controller = WalletController(api: widget.api);

  @override
  void initState() {
    super.initState();
    if (widget.isAuthenticated() && widget.api.hasToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.load();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WalletScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The tab stays mounted through login (ADR-112 lazy mount): pick the
    // ledger up as soon as the shell rebuilds us as authenticated.
    if (_controller.status == WalletStatus.initial &&
        widget.isAuthenticated() &&
        widget.api.hasToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.load();
      });
    }
    if (oldWidget.refreshTick != widget.refreshTick &&
        widget.isAuthenticated() &&
        widget.api.hasToken &&
        _controller.status != WalletStatus.loading) {
      _controller.load();
    }
  }

  void _openPayments() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentHistoryScreen(
          api: widget.api,
          onLoginRequired: widget.onLoginRequired,
        ),
      ),
    );
  }

  Future<void> _openReturnSheet() async {
    final request = await showModalBottomSheet<ReturnRequest>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ShodashaTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ShodashaTheme.radiusSheet),
        ),
      ),
      builder: (_) =>
          ReturnSheet(api: widget.api, pickAddress: widget.pickAddress),
    );
    if (!mounted || request == null) return;
    // Prefer the server's SLA sentence; fall back to the same promise.
    final message = request.message.isNotEmpty
        ? request.message
        : 'Request filed — pickup within 10 working days.';
    // A refund is surfaced only when the server states it (never computed).
    final refund = request.refundPaise == null
        ? ''
        : ' Refund recorded: ${formatInr(request.refundPaise!)}.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$message$refund')));
    // A return changes the jar ledger server-side; re-read it instead of
    // leaving the previous deposit/dues snapshot on screen.
    _controller.load();
  }

  @override
  Widget build(BuildContext context) {
    final authenticated = widget.isAuthenticated() && widget.api.hasToken;
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: !authenticated
          ? _GuestState(onLoginRequired: widget.onLoginRequired)
          : ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => RefreshIndicator(
                color: ShodashaTheme.teal,
                onRefresh: _controller.load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    _ledgerSection(),
                    const SizedBox(height: 12),
                    _LinkCard(
                      icon: Icons.receipt_long_outlined,
                      title: 'Payments & deposits',
                      subtitle: 'UPI and cash receipts, plus deposit refunds',
                      onTap: _openPayments,
                    ),
                    const SizedBox(height: 12),
                    _ReturnsCard(onRequest: _openReturnSheet),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _ledgerSection() {
    switch (_controller.status) {
      case WalletStatus.initial:
      case WalletStatus.loading:
        return const _WalletSkeleton();
      case WalletStatus.error:
        return _ErrorCard(
          message: _controller.errorMessage ?? 'Could not load your ledger',
          onRetry: _controller.load,
        );
      case WalletStatus.loaded:
        final ledger = _controller.ledger;
        if (ledger == null) return const _WalletSkeleton();
        if (ledger.isEmpty) {
          return _EmptyLedger(
            hasHistory:
                ledger.depositPaidPaise > 0 || ledger.depositRefundedPaise > 0,
          );
        }
        return _LedgerBody(ledger: ledger);
    }
  }
}

class _LedgerBody extends StatelessWidget {
  const _LedgerBody({required this.ledger});

  final LedgerSnapshot ledger;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Solid-teal hero (donor grammar, gradient flattened): only the
        // server's wallet_held deposit is shown — no Add Money, no balance.
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ShodashaTheme.teal,
            borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'REFUNDABLE DEPOSIT',
                    style: TextStyle(
                      color: ShodashaTheme.surface.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 24,
                    color: ShodashaTheme.surface.withValues(alpha: 0.85),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                formatInr(ledger.depositHeldPaise),
                style: const TextStyle(
                  color: ShodashaTheme.surface,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Refunded after your jars are collected.',
                style: TextStyle(
                  color: ShodashaTheme.surface.withValues(alpha: 0.85),
                  fontSize: 12,
                ),
              ),
              if (ledger.heldJars > 0) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: ShodashaTheme.surface.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                  ),
                  child: Text(
                    '${ledger.heldJars} '
                    '${ledger.heldJars == 1 ? 'jar' : 'jars'} with you',
                    style: const TextStyle(
                      color: ShodashaTheme.surface,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ShodashaTheme.surface,
            border: Border.all(color: ShodashaTheme.border),
            borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'JAR LEDGER',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: ShodashaTheme.muted,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              _StatementRow(
                label: 'Jars with you',
                value: '${ledger.heldJars}',
              ),
              _StatementRow(
                label: 'Deposit paid',
                value: formatInr(ledger.depositPaidPaise),
              ),
              if (ledger.depositRefundedPaise > 0)
                _StatementRow(
                  label: 'Deposit refunded',
                  value: formatInr(ledger.depositRefundedPaise),
                ),
              _StatementRow(
                label: 'Dues',
                value: formatInr(ledger.duesPaise),
                highlight: ledger.duesPaise > 0,
              ),
              const Divider(height: 20),
              const Text(
                'Your deposit is refunded to the UPI you add when you request '
                'a jar return.',
                style: TextStyle(fontSize: 11, color: ShodashaTheme.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatementRow extends StatelessWidget {
  const _StatementRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: ShodashaTheme.muted, fontSize: 14),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: highlight ? ShodashaTheme.danger : ShodashaTheme.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLedger extends StatelessWidget {
  const _EmptyLedger({required this.hasHistory});

  final bool hasHistory;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
      ),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: ShodashaTheme.tealTint,
            child: Icon(
              Icons.account_balance_wallet_outlined,
              size: 28,
              color: ShodashaTheme.teal,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Nothing on your jar account yet',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: ShodashaTheme.ink,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'Your deposit, dues and jars will appear here after your first '
            'delivery.',
            style: TextStyle(color: ShodashaTheme.muted, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          if (hasHistory) ...[
            const SizedBox(height: 6),
            const Text(
              'Past deposits are listed under Payments & deposits.',
              style: TextStyle(color: ShodashaTheme.muted, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _WalletSkeleton extends StatelessWidget {
  const _WalletSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading your jar ledger',
      child: Column(
        children: [
          Container(
            height: 148,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: ShodashaTheme.surface,
              border: Border.all(color: ShodashaTheme.border),
              borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBox(width: 150, height: 12),
                SizedBox(height: 18),
                _SkeletonBox(width: 120, height: 30),
                SizedBox(height: 14),
                _SkeletonBox(width: 200, height: 10),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 96,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ShodashaTheme.surface,
              border: Border.all(color: ShodashaTheme.border),
              borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBox(width: 90, height: 10),
                SizedBox(height: 14),
                _SkeletonBox(width: double.infinity, height: 10),
                SizedBox(height: 10),
                _SkeletonBox(width: 200, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: ShodashaTheme.bg,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline,
            size: 40,
            color: ShodashaTheme.danger,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(color: ShodashaTheme.muted, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ShodashaTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
        side: const BorderSide(color: ShodashaTheme.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: ShodashaTheme.tealTint,
                child: Icon(icon, size: 20, color: ShodashaTheme.teal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: ShodashaTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ShodashaTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: ShodashaTheme.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReturnsCard extends StatelessWidget {
  const _ReturnsCard({required this.onRequest});

  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: ShodashaTheme.tealTint,
            child: Icon(
              Icons.assignment_return_outlined,
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
                  'Return jars',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: ShodashaTheme.ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Pickup + refund in 10 working days',
                  style: TextStyle(fontSize: 12, color: ShodashaTheme.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onRequest,
            child: const Text('Request return'),
          ),
        ],
      ),
    );
  }
}

class _GuestState extends StatelessWidget {
  const _GuestState({required this.onLoginRequired});

  final VoidCallback? onLoginRequired;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 32,
              backgroundColor: ShodashaTheme.tealTint,
              child: Icon(
                Icons.account_balance_wallet_outlined,
                size: 32,
                color: ShodashaTheme.teal,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Log in to see your jar ledger',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: ShodashaTheme.ink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Your deposit, dues and jars appear here once you log in.',
              style: TextStyle(color: ShodashaTheme.muted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            if (onLoginRequired != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onLoginRequired,
                child: const Text('Log in'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
