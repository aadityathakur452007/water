// F5 — Subscriptions: list + pause range + skip + resume. Contract §4.5
// ignore_for_file: prefer_initializing_formals
// WHY: public ctor param `api:` is the API (same pattern as F2 auth);
// private initializing formals are unusable from other libraries.
// (pause {hold_from, hold_to} → routing excluded + FCM confirm; resume
// {preferred_date} ≥24h guard → 422 + next valid date; skips {date} before
// cutoff, after → late_skip + vendor call CTA; auto-resume on hold_to).
// States.md: list skeleton → empty → error; every async op has feedback.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

const Map<String, String> subStringsHi = {
  'title': 'Subscriptions',
  'emptyTitle': 'Koi subscription nahi',
  'emptyHint': 'Repeat delivery ke liye booking sheet se subscription ban jati hai',
  'pause': 'Pause karein',
  'resume': 'Resume karein',
  'skipToday': 'Aaj skip karein',
  'skipTomorrow': 'Kal skip karein',
  'pausedBadge': 'Paused',
  'pausedUntil': 'tak band',
  'windowLabel': 'Window',
  'nextRun': 'Agli delivery',
  'pauseTitle': 'Kitne din ke liye band karna hai?',
  'fromDate': 'Kis din se',
  'toDate': 'Kis din tak',
  'pauseConfirm': 'Pause pakka karein',
  'errRange': 'End date start se aage honi chahiye',
  'resumeTitle': 'Kab se wapas shuru karein?',
  'resumeNote': 'Kam se kal se (24 ghante baad) — aaj se nahi',
  'resumeConfirm': 'Resume karein',
  'lateSkipTitle': 'Cut-off nikal gaya',
  'lateSkipBody': 'Aaj ki delivery skip nahi hui — vendor ko call karein',
  'vendorCall': 'Vendor ko call karein',
  'saved': 'Ho gaya',
  'loadFailed': 'Subscription load nahi hui',
  'offline': 'Internet nahi — dobara try karein',
  'retry': 'Dobara try karein',
  'qty': 'Jar',
};

enum SubStatus { initial, loading, loaded, error }

@immutable
class SubscriptionEntry {
  const SubscriptionEntry({
    required this.id,
    required this.label,
    required this.qty,
    required this.windowStart,
    required this.windowEnd,
    this.paused = false,
    this.holdFrom,
    this.holdTo,
    this.nextRun,
  });

  final String id;
  final String label;
  final int qty;
  final String windowStart; // '09:00'
  final String windowEnd; // '09:30'
  final bool paused;
  final String? holdFrom; // YYYY-MM-DD
  final String? holdTo; // YYYY-MM-DD
  final String? nextRun; // YYYY-MM-DD

  static SubscriptionEntry fromApi(Map<String, dynamic> j) =>
      SubscriptionEntry(
        id: (j['id'] ?? '') as String,
        label: (j['address_label'] ?? j['label'] ?? 'Address') as String,
        qty: (j['qty'] ?? 0) as int,
        windowStart: (j['window_start'] ?? '09:00') as String,
        windowEnd: (j['window_end'] ?? '09:30') as String,
        paused: (j['paused'] ?? false) as bool,
        holdFrom: j['hold_from'] as String?,
        holdTo: j['hold_to'] as String?,
        nextRun: j['next_run'] as String?,
      );
}

class SubscriptionController extends ChangeNotifier {
  SubscriptionController({required ApiClient api}) : _api = api;

  final ApiClient _api;

  SubStatus _status = SubStatus.initial;
  List<SubscriptionEntry> _items = [];
  String? _errorMessage;
  bool _busy = false;

  SubStatus get status => _status;
  List<SubscriptionEntry> get items => List.unmodifiable(_items);
  String? get errorMessage => _errorMessage;
  bool get busy => _busy;

  /// 015: pay-per-day totals — Due today (qty × rate) + Paid till now (dues).
  int duesPaise = 0;

  /// F7: server UPI intent for the outstanding dues (null when none).
  String? duesPayLink;
  int get dueTodayPaise => _items.fold(0, (s, e) => s + e.qty * 2800);

  Future<void> load() async {
    if (_status == SubStatus.loading) return;
    _status = SubStatus.loading;
    _errorMessage = null;
    _notify();
    try {
      final raw = await _api.listSubscriptions();
      _items = raw
          .whereType<Map<String, dynamic>>()
          .map(SubscriptionEntry.fromApi)
          .toList();
      try {
        final dues = await _api.billingDues();
        duesPaise = (dues['dues'] as num?)?.toInt() ?? 0;
        final link = dues['pay_link'];
        duesPayLink = link is String && link.isNotEmpty ? link : null;
      } catch (_) {
        duesPaise = 0;
        duesPayLink = null;
      }
      _status = SubStatus.loaded;
    } on ApiException catch (e) {
      _status = SubStatus.error;
      _errorMessage = e.isNetwork
          ? subStringsHi['offline']
          : subStringsHi['loadFailed'];
    } catch (_) {
      _status = SubStatus.error;
      _errorMessage = subStringsHi['loadFailed'];
    }
    _notify();
  }

  /// Pause with range validation (end > start). Returns error key or null.
  Future<String?> pause(String id, String from, String to) async {
    // Gate: hold range end > start (date.ts cross-validation pattern).
    if (to.compareTo(from) <= 0) return 'errRange';
    _busy = true;
    _notify();
    try {
      await _api.pauseSubscription(id, from, to);
      await load();
      return null;
    } on ApiException catch (e) {
      _busy = false;
      _notify();
      return e.isNetwork ? 'offline' : 'loadFailed';
    } catch (_) {
      _busy = false;
      _notify();
      return 'loadFailed';
    }
  }

  /// Resume: server guards ≥24h (422 + next valid date); we pre-check
  /// locally so users never see a dead 422 — must be ≥ tomorrow.
  Future<String?> resume(String id, String preferredDate) async {
    final today = ApiClient.dateOnly(DateTime.now());
    if (preferredDate.compareTo(today) <= 0) return 'resumeNote';
    _busy = true;
    _notify();
    try {
      await _api.resumeSubscription(id, preferredDate);
      await load();
      return null;
    } on ApiException catch (e) {
      _busy = false;
      _notify();
      return e.isNetwork ? 'offline' : 'loadFailed';
    } catch (_) {
      _busy = false;
      _notify();
      return 'loadFailed';
    }
  }

  /// Skip a day. Returns 'lateSkip' when the server says after-cutoff
  /// (contract: after cutoff → late_skip + vendor call CTA — never silent).
  Future<String?> skipToday(String id) async {
    _busy = true;
    _notify();
    try {
      await _api.skipSubscriptionDay(id, ApiClient.dateOnly(DateTime.now()));
      await load();
      return null;
    } on ApiException catch (e) {
      _busy = false;
      _notify();
      if (e.code == 'LATE_SKIP') return 'lateSkip';
      return e.isNetwork ? 'offline' : 'loadFailed';
    } catch (_) {
      _busy = false;
      _notify();
      return 'loadFailed';
    }
  }

  void _notify() {
    if (!disposed) notifyListeners();
  }

  @protected
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

/// Subscriptions tab-page.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, required this.controller});

  final SubscriptionController controller;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.controller.status == SubStatus.initial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.controller.load();
      });
    }
  }

  void _toast(String key) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(subStringsHi[key] ?? key)),
    );
  }

  Future<void> _pauseSheet(SubscriptionEntry s) async {
    final base = DateTime.now().add(const Duration(days: 1));
    var from = base;
    var to = base.add(const Duration(days: 7));
    final err = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subStringsHi['pauseTitle']!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                Text(subStringsHi['fromDate']!),
                OutlinedButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: from,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setSheet(() => from = d);
                  },
                  child: Text(ApiClient.dateOnly(from)),
                ),
                const SizedBox(height: 8),
                Text(subStringsHi['toDate']!),
                OutlinedButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: to,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setSheet(() => to = d);
                  },
                  child: Text(ApiClient.dateOnly(to)),
                ),
                if (to.compareTo(from) <= 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      subStringsHi['errRange']!,
                      style: const TextStyle(color: ShodashaTheme.danger),
                    ),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(
                      '${ApiClient.dateOnly(from)}|${ApiClient.dateOnly(to)}',
                    ),
                    child: Text(subStringsHi['pauseConfirm']!),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (err == null || !mounted) return;
    final parts = err.split('|');
    final e = await widget.controller.pause(s.id, parts[0], parts[1]);
    if (!mounted) return;
    _toast(e ?? 'saved');
  }

  Future<void> _resumeSheet(SubscriptionEntry s) async {
    final first = DateTime.now().add(const Duration(days: 2)); // ≥24h guard
    final picked = await showDatePicker(
      context: context,
      initialDate: first,
      firstDate: first,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: subStringsHi['resumeNote'],
    );
    if (picked == null || !mounted) return;
    final e = await widget.controller.resume(
      s.id,
      ApiClient.dateOnly(picked),
    );
    if (!mounted) return;
    _toast(e ?? 'saved');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(title: Text(subStringsHi['title']!)),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          if (c.status == SubStatus.loading && c.items.isEmpty) {
            // Phase 9 §9.1: list skeleton (was a bare spinner) — same
            // blueTint rhythm as the orders list.
            return const _SubsSkeleton();
          }
          if (c.status == SubStatus.error && c.items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c.errorMessage ?? ''),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: c.load,
                    child: Text(subStringsHi['retry']!),
                  ),
                ],
              ),
            );
          }
          if (c.items.isEmpty) {
            return RefreshIndicator(
              onRefresh: c.load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const _MonthlyPlanCalculator(),
                  const SizedBox(height: 24),
                  Center(
                    child: Column(
                      children: [
                        Text(
                          subStringsHi['emptyTitle']!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subStringsHi['emptyHint']!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: ShodashaTheme.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: c.load,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: c.items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                // 015: totals header — Due today + Paid till now (pay-per-day).
                if (i == 0) {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ShodashaTheme.blueTint,
                      borderRadius:
                          BorderRadius.circular(ShodashaTheme.radius),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Due today Rs ${c.dueTodayPaise ~/ 100} • Paid till now Rs ${c.duesPaise ~/ 100}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        // F7: server UPI intent for outstanding dues.
                        if (c.duesPayLink != null)
                          TextButton(
                            onPressed: () => launchUrl(
                              Uri.parse(c.duesPayLink!),
                              mode: LaunchMode.externalApplication,
                            ),
                            child: const Text('Dues chukayein'),
                          ),
                      ],
                    ),
                  );
                }
                final s = c.items[i - 1];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: ShodashaTheme.border),
                    borderRadius:
                        BorderRadius.circular(ShodashaTheme.radius),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (s.paused)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: ShodashaTheme.blueTint,
                                borderRadius: BorderRadius.circular(
                                  ShodashaTheme.radius,
                                ),
                              ),
                              child: Text(
                                subStringsHi['pausedBadge']!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: ShodashaTheme.blue,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${subStringsHi['qty']}: ${s.qty} • '
                        '${subStringsHi['windowLabel']}: '
                        '${s.windowStart}–${s.windowEnd}',
                        style: const TextStyle(
                          color: ShodashaTheme.muted,
                          fontSize: 13,
                        ),
                      ),
                      if (s.paused && s.holdTo != null)
                        Text(
                          '${subStringsHi['pausedUntil']} ${s.holdTo}',
                          style: const TextStyle(
                            color: ShodashaTheme.muted,
                            fontSize: 13,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        children: [
                          if (!s.paused)
                            TextButton(
                              onPressed: () => _pauseSheet(s),
                              child: Text(subStringsHi['pause']!),
                            )
                          else
                            TextButton(
                              onPressed: () => _resumeSheet(s),
                              child: Text(subStringsHi['resume']!),
                            ),
                          if (!s.paused)
                            TextButton(
                              onPressed: () async {
                                final e = await c.skipToday(s.id);
                                if (!mounted) return;
                                if (e == 'lateSkip') {
                                  // State.context after State.mounted guard
                                  // (use_build_context_synchronously).
                                  showDialog<void>(
                                    context: this.context,
                                    builder: (ctx) => AlertDialog(
                                      shape: ShodashaTheme.shape,
                                      title:
                                          Text(subStringsHi['lateSkipTitle']!),
                                      content:
                                          Text(subStringsHi['lateSkipBody']!),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(),
                                          child: const Text('Theek hai'),
                                        ),
                                      ],
                                    ),
                                  );
                                } else if (e != null) {
                                  _toast(e);
                                }
                              },
                              child: Text(subStringsHi['skipToday']!),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Phase 9 §9.1: first-load skeleton matching the sub-row rhythm
/// (same blueTint boxes as the orders list).
class _SubsSkeleton extends StatelessWidget {
  const _SubsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: 3,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, _) => Container(
        height: 88,
        decoration: BoxDecoration(
          color: ShodashaTheme.blueTint,
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        ),
      ),
    );
  }
}

/// Interactive Monthly Plan Calculator & Information Card.
/// Explains the 30 jars × ₹30 = ₹900/mo math, deposit refund, and Prepaid vs Postpaid modes.
class _MonthlyPlanCalculator extends StatefulWidget {
  const _MonthlyPlanCalculator();

  @override
  State<_MonthlyPlanCalculator> createState() => _MonthlyPlanCalculatorState();
}

class _MonthlyPlanCalculatorState extends State<_MonthlyPlanCalculator> {
  int _jarsPerDelivery = 1;
  int _deliveriesPerMonth = 30; // 30 = Daily, 15 = Alternate, 8 = Twice a week
  bool _isPrepaid = true;
  static const int _ratePerJar = 30;
  static const int _depositPerJar = 150;

  @override
  Widget build(BuildContext context) {
    final totalJars = _jarsPerDelivery * _deliveriesPerMonth;
    final waterBill = totalJars * _ratePerJar;
    final deposit = _jarsPerDelivery * _depositPerJar;

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
            children: [
              const Icon(Icons.calculate_outlined, color: ShodashaTheme.blue, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Mahina Subscription Calculator',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: ShodashaTheme.ink,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: ShodashaTheme.blueTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Plans',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ShodashaTheme.blue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '1. Roz kitne jar chahiye?',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Row(
            children: [1, 2, 3].map((qty) {
              final sel = _jarsPerDelivery == qty;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('$qty Jar${qty > 1 ? "s" : ""}'),
                  selected: sel,
                  selectedColor: ShodashaTheme.blueTint,
                  onSelected: (_) => setState(() => _jarsPerDelivery = qty),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          const Text(
            '2. Delivery frequency:',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Rozana (30 din)'),
                selected: _deliveriesPerMonth == 30,
                selectedColor: ShodashaTheme.blueTint,
                onSelected: (_) => setState(() => _deliveriesPerMonth = 30),
              ),
              ChoiceChip(
                label: const Text('Alternate (15 din)'),
                selected: _deliveriesPerMonth == 15,
                selectedColor: ShodashaTheme.blueTint,
                onSelected: (_) => setState(() => _deliveriesPerMonth = 15),
              ),
              ChoiceChip(
                label: const Text('Hafte me 2 din (8 din)'),
                selected: _deliveriesPerMonth == 8,
                selectedColor: ShodashaTheme.blueTint,
                onSelected: (_) => setState(() => _deliveriesPerMonth = 8),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '3. Payment Mode:',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _isPrepaid = true),
                  borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _isPrepaid ? ShodashaTheme.blueTint : ShodashaTheme.bg,
                      border: Border.all(
                        color: _isPrepaid ? ShodashaTheme.blue : ShodashaTheme.border,
                        width: _isPrepaid ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Prepaid Monthly',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Mahine ki shuruat me UPI se',
                          style: TextStyle(fontSize: 11, color: ShodashaTheme.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _isPrepaid = false),
                  borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: !_isPrepaid ? ShodashaTheme.blueTint : ShodashaTheme.bg,
                      border: Border.all(
                        color: !_isPrepaid ? ShodashaTheme.blue : ShodashaTheme.border,
                        width: !_isPrepaid ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Postpaid / Per-day',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Har delivery par ya hisaab se',
                          style: TextStyle(fontSize: 11, color: ShodashaTheme.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Calculation Breakdown
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
              border: Border.all(color: ShodashaTheme.border),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$totalJars Jars ($totalJars × ₹$_ratePerJar)',
                      style: const TextStyle(fontSize: 13, color: ShodashaTheme.ink),
                    ),
                    Text(
                      '₹$waterBill/month',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Refundable Deposit ($_jarsPerDelivery jar)',
                      style: const TextStyle(fontSize: 12, color: ShodashaTheme.muted),
                    ),
                    Text(
                      '₹$deposit (one-time)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: ShodashaTheme.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16, color: ShodashaTheme.border),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Mahina Kharcha:',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    Text(
                      '₹$waterBill',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: ShodashaTheme.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  '💡 Service chhodne par Jar Deposit aapke UPI par turant refund ho jata hai.',
                  style: TextStyle(fontSize: 11, color: ShodashaTheme.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
