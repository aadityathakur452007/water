// Notifications derived from the account's real orders/subscriptions.
// The donor app kept a local list of fake "delivery partner" and "wallet"
// notifications. This screen never invents events; it reads the same server
// state the Orders and Subscriptions tabs show.

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/constants/app_constants.dart';
import '../orders/orders_controller.dart';

class DonorNotificationsScreen extends StatefulWidget {
  const DonorNotificationsScreen({
    super.key,
    required this.api,
    required this.orders,
  });

  final ApiClient api;
  final OrdersController orders;

  @override
  State<DonorNotificationsScreen> createState() =>
      _DonorNotificationsScreenState();
}

class _DonorNotificationsScreenState extends State<DonorNotificationsScreen> {
  List<_Note> _subs = const [];
  bool _loadingSubs = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.orders.status == OrdersListStatus.initial) {
      widget.orders.load();
    }
    _loadSubs();
  }

  Future<void> _loadSubs() async {
    setState(() {
      _loadingSubs = true;
      _error = null;
    });
    try {
      final rows = await widget.api.listSubscriptions();
      if (!mounted) return;
      setState(() {
        _subs = [
          for (final row in rows)
            if (row is Map<String, dynamic>)
              _Note(
                icon: Icons.autorenew,
                title: 'Subscription ${_status(row)}',
                body:
                    '${(row['qty'] ?? 1)} x 20L · next delivery ${_date(row['next_run'])}',
                at: _parse(row['next_run']),
              ),
        ];
        _loadingSubs = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.isOffline
            ? 'No internet — could not load subscription updates.'
            : e.isServerError
            ? 'Server problem — could not load subscription updates.'
            : 'Could not load subscription updates.';
        _loadingSubs = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load subscription updates.';
        _loadingSubs = false;
      });
    }
  }

  Future<void> _refresh() async {
    await Future.wait([widget.orders.refresh(), _loadSubs()]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: const Text(
          'NOTIFICATIONS',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: Colors.white,
            letterSpacing: 1.1,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.orders,
        builder: (context, _) {
          final notes =
              <_Note>[
                for (final o in widget.orders.allOrders.take(20))
                  _Note(
                    icon: _orderIcon(o.state),
                    title: 'Order #${o.id} · ${o.state.name}',
                    body: o.itemSummary.isEmpty
                        ? 'Tap to see delivery details.'
                        : o.itemSummary,
                    at: o.createdAt,
                  ),
                ..._subs,
              ]..sort((a, b) {
                final ad = a.at;
                final bd = b.at;
                if (ad == null && bd == null) return 0;
                if (ad == null) return 1;
                if (bd == null) return -1;
                return bd.compareTo(ad);
              });

          final orderError = widget.orders.errorMessage == null
              ? null
              : widget.orders.isOffline
              ? 'No internet — could not refresh order updates.'
              : 'Could not refresh order updates.';
          final banners = <Widget>[
            if (orderError != null)
              _Banner(message: orderError, onRetry: _refresh),
            if (_error != null) _Banner(message: _error!, onRetry: _refresh),
          ];
          final loading =
              (widget.orders.status == OrdersListStatus.initial ||
                      widget.orders.status == OrdersListStatus.loading) &&
                  widget.orders.allOrders.isEmpty ||
              _loadingSubs && _subs.isEmpty;

          if (notes.isEmpty && banners.isEmpty && loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                ...banners,
                if (banners.isNotEmpty) const SizedBox(height: 4),
                if (notes.isEmpty && banners.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 100),
                    child: Column(
                      children: [
                        Icon(
                          Icons.notifications_none,
                          size: 44,
                          color: AppColors.textSecondary,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'No order or subscription updates yet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  for (final note in notes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _NoteTile(note: note),
                    ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  static IconData _orderIcon(OrderState state) {
    if (state == OrderState.delivered) return Icons.check_circle_outline;
    if (state == OrderState.cancelled || state == OrderState.failed) {
      return Icons.error_outline;
    }
    return Icons.local_shipping_outlined;
  }

  static String _status(Map<String, dynamic> row) {
    if (row['status'] != null) return '${row['status']}';
    if (row['paused'] == true) return 'paused';
    if (row['canceled'] == true) return 'cancelled';
    return 'active';
  }

  static DateTime? _parse(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static String _date(Object? value) {
    final parsed = _parse(value);
    if (parsed == null) return 'not scheduled';
    final local = parsed.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF9C3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDE047)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 17, color: Color(0xFF854D0E)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Color(0xFF713F12),
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _Note {
  const _Note({
    required this.icon,
    required this.title,
    required this.body,
    required this.at,
  });

  final IconData icon;
  final String title;
  final String body;
  final DateTime? at;
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note});

  final _Note note;

  @override
  Widget build(BuildContext context) {
    final at = note.at?.toLocal();
    final date = at == null
        ? ''
        : '${at.day}/${at.month}/${at.year} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(note.icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  note.body,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (date.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    date,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
