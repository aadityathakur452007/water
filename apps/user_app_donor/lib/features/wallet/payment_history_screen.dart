// S7 — Payments & deposits history, fed only by GET /v1/payments/me.
//
// Every amount/status/date is a server field (no client math). States.md
// coverage: loading (spinner), loaded (receipt cards), empty (honest copy),
// error (message + retry), unauthorised (login prompt, zero network),
// session-expired (401/403 copy), refreshing (pull-to-refresh keeps cards).

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
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
  const PaymentHistoryScreen({
    super.key,
    required this.api,
    this.onLoginRequired,
  });

  final ApiClient api;

  /// 401 fallback CTA; the root navigator normally pops to login first.
  final VoidCallback? onLoginRequired;

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  /// Server default page size for GET /payments/me; it has no cursor, so a
  /// full page means there may be older receipts we cannot reach (P2-8).
  static const int _pageLimit = 50;

  bool _loading = true;
  bool _isAuthError = false;
  String? _error;
  List<PaymentRecord> _payments = const [];

  bool get _isCapped => _payments.length >= _pageLimit;

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
      _isAuthError = false;
    });
    try {
      final list = await widget.api.listUserPayments(limit: _pageLimit);
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
        final auth = e.statusCode == 401 || e.statusCode == 403;
        _isAuthError = auth;
        _error = auth
            ? 'Session expired — log in again'
            : e.isOffline
            ? 'No internet — try again'
            : e.isServerError
            ? 'Server problem — try again'
            : 'Could not load payments';
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

  /// Close this route before the shell shows login (no dead-end stack).
  void _signIn() {
    Navigator.of(context).pop();
    widget.onLoginRequired?.call();
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: ShodashaTheme.teal),
      );
    }
    if (_error != null) {
      return _ErrorState(
        message: _error!,
        onRetry: _fetch,
        onSignIn: _isAuthError ? _signIn : null,
      );
    }
    if (_payments.isEmpty) return const _EmptyState();

    return RefreshIndicator(
      color: ShodashaTheme.teal,
      onRefresh: _fetch,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        // The server caps /payments/me with no cursor, so we can only show
        // the newest page. Say so instead of faking a "load more" (P2-8).
        itemCount: _payments.length + (_isCapped ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == _payments.length) return const _CapNote();
          return _PaymentCard(
            payment: _payments[index],
            date: _formatDate(_payments[index].dateIso),
          );
        },
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
                        formatInr(payment.amountPaise),
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
                    'Deposit: ${formatInr(payment.depositPaise)}',
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

class _CapNote extends StatelessWidget {
  const _CapNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ShodashaTheme.bg,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: ShodashaTheme.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing the latest 50 payments. Older receipts are not '
              'available in the app yet — contact support at $kSupportPhone '
              'if you need one.',
              style: const TextStyle(fontSize: 12, color: ShodashaTheme.muted),
            ),
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
  const _ErrorState({
    required this.message,
    required this.onRetry,
    this.onSignIn,
  });

  final String message;
  final Future<void> Function() onRetry;
  final VoidCallback? onSignIn;

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
            if (onSignIn != null) ...[
              ElevatedButton(onPressed: onSignIn, child: const Text('Sign in')),
              const SizedBox(height: 8),
            ],
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

String _titleCase(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
