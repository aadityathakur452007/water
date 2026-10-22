// Donor wallet screen, backed by the real jar ledger.
//
// The donor hero showed a fake ₹450 balance and an "Add Money" button, and
// the transaction list was hardcoded. The backend has no wallet balance/top-up;
// it has deposits, held jars, dues and receipts. This screen shows those, with
// the donor card/list grammar. No invented money.

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/constants/app_constants.dart';
import '../../core/money.dart';
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _paymentsError = 'Could not load recent receipts';
        _paymentsLoading = false;
      });
    }
  }

  Future<void> _openReturnSheet() async {
    final request = await showModalBottomSheet<ReturnRequest>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) =>
          ReturnSheet(api: widget.api, pickAddress: widget.pickAddress),
    );
    if (!mounted || request == null) return;
    final message = request.message.isNotEmpty
        ? request.message
        : 'Pickup requested.';
    final refund = request.refundPaise == null
        ? ''
        : ' Refund recorded: ${formatInr(request.refundPaise!)}.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$message$refund')));
    _load();
  }

  void _openPayments() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PaymentHistoryScreen(api: widget.api),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'SHODASHA WALLET',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: Colors.white,
            letterSpacing: 1.1,
          ),
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              children: [
                if (_controller.status == WalletStatus.loading ||
                    _controller.status == WalletStatus.initial)
                  const _WalletSkeleton()
                else if (_controller.status == WalletStatus.error)
                  _WalletError(
                    message:
                        _controller.errorMessage ??
                        'Could not load your ledger',
                    onRetry: _load,
                  )
                else if (_controller.ledger != null)
                  _ledgerBody(_controller.ledger!),
                const SizedBox(height: 12),
                _actionTile(
                  icon: Icons.receipt_long_outlined,
                  color: const Color(0xFF0284C7),
                  title: 'Payments & deposits',
                  subtitle: 'UPI and cash receipts, plus deposit refunds',
                  onTap: _openPayments,
                ),
                const SizedBox(height: 10),
                _actionTile(
                  icon: Icons.recycling_outlined,
                  color: AppColors.primary,
                  title: 'Return empty jars',
                  subtitle: 'Request a pickup and refund of your deposit',
                  onTap: _openReturnSheet,
                ),
                if ((_controller.ledger?.duesPaise ?? 0) > 0) ...[
                  const SizedBox(height: 10),
                  _actionTile(
                    icon: Icons.payments_outlined,
                    color: AppColors.money,
                    title: 'Outstanding dues',
                    subtitle:
                        '${formatInr(_controller.ledger!.duesPaise)} — pay from Subscriptions',
                    onTap: widget.onOpenSubscriptions,
                  ),
                ],
                const SizedBox(height: 22),
                const Text(
                  'RECENT TRANSACTIONS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 10),
                if (_paymentsLoading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_paymentsError != null)
                  Text(
                    _paymentsError!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  )
                else if (_payments.isEmpty)
                  const Text(
                    'No receipts yet.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  )
                else
                  ..._payments.map(_paymentTile),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _ledgerBody(LedgerSnapshot ledger) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
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
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Icon(
                    Icons.account_balance_wallet,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                formatInr(ledger.depositHeldPaise),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Refunded after your jars are collected.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${ledger.heldJars} ${ledger.heldJars == 1 ? 'jar' : 'jars'} with you',
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
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CAN SECURITY LEDGER',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
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

  Widget _row(String label, String value, {bool emphasis = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: emphasis ? const Color(0xFFB91C1C) : AppColors.textPrimary,
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
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: Color(0xFF94A3B8),
          size: 20,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _paymentTile(PaymentRecord p) {
    final date = p.dateIso == null
        ? '—'
        : DateTime.tryParse(
                p.dateIso!,
              )?.toLocal().toString().split(' ').first ??
              '—';
    final isCredit = p.isRefund || p.depositPaise > 0 && p.amountPaise == 0;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isCredit
              ? const Color(0xFFDCFCE7)
              : const Color(0xFFFEE2E2),
          child: Icon(
            isCredit ? Icons.arrow_downward : Icons.arrow_outward,
            color: isCredit ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
            size: 18,
          ),
        ),
        title: Text(
          p.isRefund
              ? 'Deposit refund'
              : '${p.method} payment · ${p.jarsCount} jar${p.jarsCount == 1 ? '' : 's'}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
        subtitle: Text(
          date,
          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
        ),
        trailing: Text(
          formatInr(p.amountPaise),
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 14,
            color: isCredit ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
          ),
        ),
      ),
    );
  }
}

class _WalletSkeleton extends StatelessWidget {
  const _WalletSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
    );
  }
}

class _WalletError extends StatelessWidget {
  const _WalletError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off, color: AppColors.textSecondary),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
