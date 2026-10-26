// Donor wallet: the real jar ledger (deposits, held jars, dues) plus the
// latest receipts. No invented balance and no top-up button — the backend has
// neither. Cached rows stay visible, marked stale, when a refresh fails.

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../shared/ui/app_banner.dart';
import '../../shared/ui/app_button.dart';
import '../../shared/ui/app_card.dart';
import '../../shared/ui/app_icon_button.dart';
import '../../shared/ui/app_state_view.dart';
import '../../shared/ui/section_header.dart';
import '../returns/return_sheet.dart';
import '../returns/returns_controller.dart';
import 'payment_history_screen.dart';
import 'wallet_controller.dart';

class DonorWalletScreen extends StatefulWidget {
  const DonorWalletScreen({
    super.key,
    required this.api,
    required this.onOpenSubscriptions,
    this.pickAddress,
    this.refreshTick = 0,
  });

  final ApiClient api;
  final VoidCallback onOpenSubscriptions;
  final ReturnAddressPicker? pickAddress;
  final int refreshTick;

  @override
  State<DonorWalletScreen> createState() => _DonorWalletScreenState();
}

class _DonorWalletScreenState extends State<DonorWalletScreen> {
  late final WalletController _controller = WalletController(api: widget.api);
  List<PaymentRecord> _payments = const [];
  bool _paymentsLoading = true;
  String? _paymentsError;
  bool _pushing = false;

  @override
  void initState() {
    super.initState();
    if (widget.api.hasToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  @override
  void didUpdateWidget(covariant DonorWalletScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick && widget.api.hasToken) {
      _load();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!widget.api.hasToken) return;
    await Future.wait([_controller.load(), _loadPayments()]);
  }

  Future<void> _loadPayments() async {
    if (!mounted) return;
    setState(() {
      _paymentsLoading = true;
      _paymentsError = null;
    });
    try {
      final rows = await widget.api.listUserPayments(limit: 3);
      if (!mounted) return;
      setState(() {
        _payments = [
          for (final row in rows)
            if (row is Map<String, dynamic>) PaymentRecord.fromApi(row),
        ];
        _paymentsLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _paymentsError = e.isOffline
            ? 'No internet — showing the receipts already loaded.'
            : e.isServerError
            ? 'Server problem — showing the receipts already loaded.'
            : 'Could not refresh receipts.';
        _paymentsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _paymentsError = 'Could not refresh receipts.';
        _paymentsLoading = false;
      });
    }
  }

  Future<void> _openReturnSheet() async {
    final held = _controller.ledger?.heldJars ?? 0;
    if (held <= 0) return;
    final request = await showModalBottomSheet<ReturnRequest>(
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
      builder: (_) => ReturnSheet(
        api: widget.api,
        pickAddress: widget.pickAddress,
        heldJars: held,
      ),
    );
    if (!mounted || request == null) return;
    await _load();
  }

  Future<void> _openPayments() async {
    if (_pushing) return;
    _pushing = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PaymentHistoryScreen(api: widget.api),
        ),
      );
    } finally {
      _pushing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShodashaTheme.bg,
      appBar: AppBar(
        backgroundColor: ShodashaTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        shape: const Border(bottom: BorderSide(color: ShodashaTheme.border)),
        title: const Text(
          'Wallet',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: ShodashaTheme.ink,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          AppIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh wallet',
            onPressed: _controller.isRefreshing ? null : _load,
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final c = _controller;
          final ledger = c.ledger;
          if (c.status == WalletStatus.loading && ledger == null) {
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                AppStateView.loading(
                  lines: 4,
                  message: 'Loading your jar ledger',
                ),
              ],
            );
          }
          if (c.status == WalletStatus.error && ledger == null) {
            return AppStateView.error(
              isNetwork: c.isOffline,
              title: c.isOffline ? null : 'Could not load your wallet',
              message: c.errorMessage,
              onRetry: _load,
            );
          }
          return RefreshIndicator(
            color: ShodashaTheme.tealDeep,
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: [
                if (c.isOffline)
                  AppBanner.offline(
                    message:
                        'Showing the ledger from your last successful refresh.',
                    onRetry: _load,
                  )
                else if (c.isStale)
                  AppBanner.stale(
                    message: c.isServerError
                        ? 'Server problem — showing your last ledger.'
                        : 'Could not refresh — showing your last ledger.',
                    onRetry: _load,
                  ),
                if (ledger != null) ...[
                  if (c.isOffline || c.isStale)
                    const SizedBox(height: AppSpacing.sm),
                  if (ledger.duesPaise > 0) ...[
                    _duesCard(ledger.duesPaise),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  _ledgerBody(ledger),
                  const SizedBox(height: AppSpacing.md),
                  _actionTile(
                    icon: Icons.receipt_long_outlined,
                    color: ShodashaTheme.blue,
                    title: 'Payments & deposits',
                    subtitle: 'UPI and cash receipts, plus deposit refunds',
                    onTap: _openPayments,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (ledger.heldJars > 0)
                    _actionTile(
                      icon: Icons.recycling_outlined,
                      color: ShodashaTheme.tealDeep,
                      title: 'Return empty jars',
                      subtitle:
                          '${ledger.heldJars} ${ledger.heldJars == 1 ? 'jar' : 'jars'} '
                          'ready — request a pickup and refund',
                      onTap: _openReturnSheet,
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(
                        'No empty jars to return yet.',
                        style: TextStyle(
                          fontSize: 12,
                          color: ShodashaTheme.muted,
                        ),
                      ),
                    ),
                  SectionHeader(
                    title: 'Recent receipts',
                    trailing: _payments.isEmpty
                        ? null
                        : TextButton(
                            onPressed: _openPayments,
                            child: const Text('See all'),
                          ),
                  ),
                  if (_paymentsLoading && _payments.isEmpty)
                    AppStateView.loading(lines: 2, message: 'Loading receipts')
                  else if (_paymentsError != null)
                    AppBanner.stale(
                      message: _paymentsError!,
                      onRetry: _loadPayments,
                    )
                  else if (_payments.isEmpty)
                    AppStateView.empty(
                      icon: Icons.receipt_outlined,
                      title: 'No receipts yet',
                      message:
                          'Payments and deposit refunds will appear here after '
                          'your first delivery.',
                    )
                  else
                    ..._payments.map(_paymentTile),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _ledgerBody(LedgerSnapshot ledger) {
    if (ledger.isEmpty) {
      return AppStateView.empty(
        icon: Icons.water_drop_outlined,
        title: 'No jars with you yet',
        message:
            'When your first 20L jar is delivered, its refundable deposit and '
            'any dues will appear here.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: ShodashaTheme.tealDeep,
            borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Refundable deposit',
                      style: TextStyle(
                        color: ShodashaTheme.surface,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    color: Colors.white.withValues(alpha: 0.85),
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                formatInr(ledger.depositHeldPaise),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Refunded after your jars are collected.',
                style: TextStyle(color: ShodashaTheme.surface, fontSize: 12),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                ),
                child: Text(
                  '${ledger.heldJars} '
                  '${ledger.heldJars == 1 ? 'jar' : 'jars'} with you',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Deposit details',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ShodashaTheme.ink,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _row('Jars with you', '${ledger.heldJars}'),
              _row('Deposit paid', formatInr(ledger.depositPaidPaise)),
              if (ledger.depositRefundedPaise > 0)
                _row(
                  'Deposit refunded',
                  formatInr(ledger.depositRefundedPaise),
                ),
              _row(
                'Outstanding dues',
                formatInr(ledger.duesPaise),
                emphasis: ledger.duesPaise > 0,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _duesCard(int duesPaise) {
    return AppCard(
      borderColor: ShodashaTheme.solarBorder,
      color: ShodashaTheme.solarTint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 20,
                color: ShodashaTheme.warning,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${formatInr(duesPaise)} in outstanding dues',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.onSolar,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Clear dues to keep cash on delivery available and avoid holds on '
            'future jars.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: ShodashaTheme.onSolar,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Review dues',
            kind: AppButtonKind.money,
            height: 48,
            onPressed: widget.onOpenSubscriptions,
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool emphasis = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: ShodashaTheme.muted),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: emphasis ? ShodashaTheme.danger : ShodashaTheme.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: ShodashaTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: ShodashaTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Icon(
            Icons.chevron_right_rounded,
            color: ShodashaTheme.muted,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _paymentTile(PaymentRecord p) {
    final date = _shortDate(p.dateIso);
    final isCredit = p.isRefund || (p.depositPaise > 0 && p.amountPaise == 0);
    final title = p.isRefund
        ? 'Deposit refund'
        : '${_methodLabel(p.method)} payment';
    final detail = [
      if (p.jarsCount > 0)
        '${p.jarsCount} ${p.jarsCount == 1 ? 'jar' : 'jars'}',
      ?date,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: _openPayments,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isCredit
                    ? ShodashaTheme.greenTint
                    : ShodashaTheme.blueTint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isCredit
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_outward_rounded,
                color: isCredit
                    ? ShodashaTheme.successDark
                    : ShodashaTheme.blue,
                size: 18,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: ShodashaTheme.ink,
                    ),
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: ShodashaTheme.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              isCredit
                  ? '+${formatInr(p.amountPaise)}'
                  : formatInr(p.amountPaise),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: isCredit ? ShodashaTheme.successDark : ShodashaTheme.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String? _shortDate(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso);
    if (d == null) return null;
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
    final local = d.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  static String _methodLabel(String method) {
    final m = method.trim();
    if (m.isEmpty) return 'Payment';
    if (m.toLowerCase() == 'upi') return 'UPI';
    if (m.toLowerCase() == 'cod') return 'Cash';
    return m[0].toUpperCase() + m.substring(1);
  }
}
