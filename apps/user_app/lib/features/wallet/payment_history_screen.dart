// S7 — Payments & deposits history, fed only by GET /v1/payments/me.
//
// Every amount/status/date is a server field (no client math). States.md
// coverage: loading (spinner), loaded (receipt cards), empty (honest copy),
// error (message + retry), unauthorised (login prompt, zero network),
// session-expired (401/403 copy), refreshing (pull-to-refresh keeps cards).

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

/// One receipt row from GET /v1/payments/me. Field names mirror the server
/// (payment_repo.list_user_payments) — no rupee doubles, integer paise only.
@immutable
class PaymentRecord {
  const PaymentRecord({
    required this.amountPaise,
    required this.method,
    required this.status,
    required this.jarsCount,
    required this.depositPaise,
    required this.dateIso,
    required this.providerRef,
  });

  final int amountPaise;
  final String method;
  final String status;
  final int jarsCount;
  final int depositPaise;
  final String? dateIso;
  final String providerRef;

  bool get isPaid => status == 'paid';
  bool get isRefund => status == 'refunded';

  static PaymentRecord fromApi(Map<String, dynamic> p) => PaymentRecord(
    amountPaise: _int(p['amount']),
    method: (p['method'] ?? 'upi').toString().toUpperCase(),
    status: (p['status'] ?? 'paid').toString().toLowerCase(),
    jarsCount: _int(p['jars_count']),
    depositPaise: _int(p['deposit_due']),
    dateIso: (p['verified_at'] ?? p['created_at']) as String?,
    providerRef: (p['provider_ref'] ?? '').toString(),
  );
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<PaymentRecord> _payments = const [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    // Contract §4: payments are account data. Guard before the socket so a
    // guest never fires a 401 storm (ADR-112).
    if (!widget.api.hasToken) {
      setState(() {
        _loading = false;
        _error = 'Log in to view your payments';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.api.listUserPayments(limit: 50);
      if (!mounted) return;
      setState(() {
        _payments = [
          for (final row in list)
            if (row is Map<String, dynamic>) PaymentRecord.fromApi(row),
        ];
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = (e.statusCode == 401 || e.statusCode == 403)
            ? 'Session expired — log in again'
            : (e.isNetwork
                  ? 'No internet — try again'
                  : 'Could not load payments');
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load payments';
        _loading = false;
      });
    }
  }

  /// Legacy date format ported verbatim (no intl dependency).
  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
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
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $hour:$min $ampm';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payments & deposits')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: ShodashaTheme.teal),
      );
    }
    if (_error != null) return _ErrorState(message: _error!, onRetry: _fetch);
    if (_payments.isEmpty) return const _EmptyState();

    return RefreshIndicator(
      color: ShodashaTheme.teal,
      onRefresh: _fetch,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _payments.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _PaymentCard(
          payment: _payments[index],
          date: _formatDate(_payments[index].dateIso),
        ),
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.payment, required this.date});

  final PaymentRecord payment;
  final String date;

  @override
  Widget build(BuildContext context) {
    final (pillBg, pillFg, pillText) = payment.isPaid
        ? (ShodashaTheme.greenSoft, ShodashaTheme.greenDark, 'Paid')
        : payment.isRefund
        ? (ShodashaTheme.solarTint, ShodashaTheme.onSolar, 'Refunded')
        : (ShodashaTheme.bg, ShodashaTheme.muted, _titleCase(payment.status));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: payment.isPaid
                        ? ShodashaTheme.tealTint
                        : (payment.isRefund
                              ? ShodashaTheme.solarTint
                              : ShodashaTheme.bg),
                    child: Icon(
                      payment.isPaid
                          ? Icons.check_circle_outline
                          : (payment.isRefund ? Icons.undo : Icons.payment),
                      size: 20,
                      color: payment.isPaid
                          ? ShodashaTheme.teal
                          : (payment.isRefund
                                ? ShodashaTheme.onSolar
                                : ShodashaTheme.muted),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '₹${payment.amountPaise ~/ 100}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: ShodashaTheme.ink,
                        ),
                      ),
                      Text(
                        payment.method,
                        style: const TextStyle(
                          fontSize: 12,
                          color: ShodashaTheme.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                ),
                child: Text(
                  pillText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: pillFg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: ShodashaTheme.border),
          const SizedBox(height: 10),
          if (payment.jarsCount > 0 || payment.depositPaise > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (payment.jarsCount > 0)
                  Text(
                    '${payment.jarsCount} jars delivered',
                    style: const TextStyle(
                      fontSize: 13,
                      color: ShodashaTheme.muted,
                    ),
                  ),
                if (payment.depositPaise > 0)
                  Text(
                    'Deposit: ₹${payment.depositPaise ~/ 100}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: ShodashaTheme.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (payment.providerRef.isNotEmpty)
                Expanded(
                  child: Text(
                    'Ref: ${payment.providerRef}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: ShodashaTheme.muted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Text(
                date,
                style: const TextStyle(
                  fontSize: 11,
                  color: ShodashaTheme.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
                Icons.receipt_long_outlined,
                size: 32,
                color: ShodashaTheme.teal,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No payments yet',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: ShodashaTheme.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your UPI and cash payments and deposit refunds will appear here.',
              style: TextStyle(color: ShodashaTheme.muted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: ShodashaTheme.danger,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(color: ShodashaTheme.muted, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

String _titleCase(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
