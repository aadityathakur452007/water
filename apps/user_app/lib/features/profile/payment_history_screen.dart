// Mere Payments — Complete Payment History Screen for User App.
// Displays verified UPI & Cash transactions, deposits, and jar counts.

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key, this.api});

  final ApiClient? api;

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  bool _loading = true;
  String? _error;
  List<dynamic> _payments = [];

  @override
  void initState() {
    super.initState();
    _fetchPayments();
  }

  Future<void> _fetchPayments() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.listUserPayments(limit: 50);
      if (mounted) {
        setState(() {
          _payments = list;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.isNetwork
              ? 'Internet nahi — dobara koshish karein'
              : 'Payments load nahi hue';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Payments load karne me samasya aayi';
          _loading = false;
        });
      }
    }
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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
      appBar: AppBar(
        title: const Text('Mere Payments'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: ShodashaTheme.danger),
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: ShodashaTheme.muted, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchPayments,
                child: const Text('Dobara try karein'),
              ),
            ],
          ),
        ),
      );
    }

    if (_payments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long_outlined, size: 56, color: ShodashaTheme.muted),
              const SizedBox(height: 12),
              const Text(
                'Koi payment record nahi mila',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: ShodashaTheme.ink,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Aapke kiye gaye sabhi payments aur refunds yahan dikhenge.',
                style: TextStyle(color: ShodashaTheme.muted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchPayments,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _payments.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final p = _payments[index] as Map<String, dynamic>;
          final amountPaise = (p['amount'] ?? 0) as int;
          final amountRs = amountPaise ~/ 100;
          final method = (p['method'] ?? 'upi').toString().toUpperCase();
          final status = (p['status'] ?? 'paid').toString().toLowerCase();
          final jars = (p['jars_count'] ?? 0) as int;
          final depositPaise = (p['deposit_due'] ?? 0) as int;
          final depositRs = depositPaise ~/ 100;
          final dateStr = _formatDate((p['verified_at'] ?? p['created_at']) as String?);
          final ref = (p['provider_ref'] ?? '').toString();

          final isPaid = status == 'paid';
          final isRefund = status == 'refunded';

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ShodashaTheme.bg,
              border: Border.all(color: ShodashaTheme.border),
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isPaid
                                ? ShodashaTheme.blueTint
                                : (isRefund ? Colors.orange.shade50 : Colors.grey.shade100),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isPaid
                                ? Icons.check_circle_outline
                                : (isRefund ? Icons.undo : Icons.payment),
                            size: 20,
                            color: isPaid
                                ? ShodashaTheme.blue
                                : (isRefund ? Colors.orange.shade800 : ShodashaTheme.muted),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '₹$amountRs',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                                color: ShodashaTheme.ink,
                              ),
                            ),
                            Text(
                              method,
                              style: const TextStyle(
                                fontSize: 12,
                                color: ShodashaTheme.muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isPaid
                            ? const Color(0xFFDCFCE7)
                            : (isRefund ? const Color(0xFFFEF3C7) : const Color(0xFFF3F4F6)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isPaid ? 'Safal / Paid' : (isRefund ? 'Refunded' : status),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isPaid
                              ? ShodashaTheme.success
                              : (isRefund ? Colors.orange.shade900 : ShodashaTheme.muted),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: ShodashaTheme.border),
                const SizedBox(height: 10),
                if (jars > 0 || depositRs > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (jars > 0)
                        Text(
                          '$jars Jars delivered',
                          style: const TextStyle(fontSize: 13, color: ShodashaTheme.muted),
                        ),
                      if (depositRs > 0)
                        Text(
                          'Deposit: ₹$depositRs',
                          style: const TextStyle(
                            fontSize: 13,
                            color: ShodashaTheme.blue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (ref.isNotEmpty)
                      Expanded(
                        child: Text(
                          'Ref: $ref',
                          style: const TextStyle(fontSize: 11, color: ShodashaTheme.muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    Text(
                      dateStr,
                      style: const TextStyle(fontSize: 11, color: ShodashaTheme.muted),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
