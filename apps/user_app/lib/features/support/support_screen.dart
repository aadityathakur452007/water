// F5 — Support tab: WhatsApp entry + FAQ + complaint form. Contract §4.7
// ignore_for_file: prefer_initializing_formals
// WHY: public ctor param `api:` is the API (same pattern as F2 auth);
// private initializing formals are unusable from other libraries.
// (POST /complaints {order_id, reason_code, text ≤500}; window: 24h for
// water_quality, 3 days general; server enforces — client shows the help
// path on 422, never silently drops). NO photo field in v1 (ADR-017:
// reason codes + words; uploader must not render at all).
// Checklist (Contacting Support): entry here + from error pages, hours,
// expected response time. GET /complaints → open → progress → resolved.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

const Map<String, String> supportStringsHi = {
  'title': 'Support',
  'waTitle': 'WhatsApp par madad',
  'waSub': '8AM–8PM • orders, delivery, jar sab kuch',
  'faqTitle': 'Aksar poochhe jaane wale sawaal',
  'complaintTitle': 'Shikayat karein',
  'complaintSub': 'Order juda hoga • 24h (paani) / 3 din (baaki)',
  'myComplaints': 'Meri shikayatein',
  'reasonLabel': 'Shikayat ka kaaran',
  'orderLabel': 'Order',
  'textLabel': 'Vivaran (500 ansh tak)',
  'textError': 'Kam se kam 10 ansh likhein',
  'submit': 'Shikayat bhejein',
  'sending': 'Bheji ja rahi hai…',
  'sent': 'Shikayat darj ho gayi — 48 ghante me jawab',
  'windowExpiredTitle': 'Shikayat window nikal gayi',
  'windowExpiredBody':
      'Is order ke liye shikayat window khatam ho gayi. WhatsApp par baat karein.',
  'errServer': 'Shikayat nahi lagi — dobara try karein',
  'offline': 'Internet nahi — dobara try karein',
  'statusOpen': 'Khuli',
  'statusProgress': 'Jaanch me',
  'statusResolved': 'Hal ho gayi',
  'none': 'Abhi koi shikayat nahi',
  'waFail': 'WhatsApp nahi khula — number copy ho gaya',
};

/// The 11 contract reason codes (schema `complaints.reason_code`).
const Map<String, String> kComplaintReasonsHi = {
  'water_quality': 'Paani ki quality',
  'damaged_jar': 'Jar tooti / kharab',
  'wrong_item': 'Galat item aaya',
  'short_delivery': 'Kam jar aayi',
  'late_delivery': 'Delivery late hui',
  'deposit_dispute': 'Deposit ka hisaab',
  'cap_dispute': 'Cap ka charge',
  'duplicate_app_order': 'Duplicate order',
  'not_needed_today': 'Aaj jaroorat nahi thi',
  'vendor_behavior': 'Rider ka behavior',
  'other': 'Kuch aur',
};

enum ComplaintStatus { initial, loading, loaded, error }

@immutable
class ComplaintEntry {
  const ComplaintEntry({
    required this.id,
    required this.orderId,
    required this.reasonCode,
    required this.text,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String orderId;
  final String reasonCode;
  final String text;
  final String status; // open | progress | resolved
  final String? createdAt;

  static ComplaintEntry fromApi(Map<String, dynamic> j) => ComplaintEntry(
        id: (j['id'] ?? '') as String,
        orderId: (j['order_id'] ?? '') as String,
        reasonCode: (j['reason_code'] ?? 'other') as String,
        text: (j['text'] ?? '') as String,
        status: (j['status'] ?? 'open') as String,
        createdAt: j['created_at'] as String?,
      );
}

class SupportController extends ChangeNotifier {
  SupportController({required ApiClient api}) : _api = api;

  final ApiClient _api;

  ComplaintStatus _status = ComplaintStatus.initial;
  List<ComplaintEntry> _items = [];
  String? _errorMessage;
  bool _busy = false;
  String? _lastError;

  ComplaintStatus get status => _status;
  List<ComplaintEntry> get items => List.unmodifiable(_items);
  String? get errorMessage => _errorMessage;
  bool get busy => _busy;
  String? get lastError => _lastError;

  Future<void> load() async {
    if (_status == ComplaintStatus.loading) return;
    _status = ComplaintStatus.loading;
    _errorMessage = null;
    _notify();
    try {
      final raw = await _api.listComplaints();
      _items = raw
          .whereType<Map<String, dynamic>>()
          .map(ComplaintEntry.fromApi)
          .toList();
      _status = ComplaintStatus.loaded;
    } on ApiException catch (e) {
      _status = ComplaintStatus.error;
      _errorMessage = e.isNetwork
          ? supportStringsHi['offline']
          : supportStringsHi['errServer'];
    } catch (_) {
      _status = ComplaintStatus.error;
      _errorMessage = supportStringsHi['errServer'];
    }
    _notify();
  }

  /// POST /complaints. Returns error-string-key or null on success.
  /// Server 422 (window) → caller shows the help-contact path, never hides.
  Future<String?> submit({
    required String orderId,
    required String reasonCode,
    required String text,
  }) async {
    _busy = true;
    _lastError = null;
    _notify();
    try {
      await _api.createComplaint(
        orderId: orderId,
        reasonCode: reasonCode,
        text: text,
      );
      await load();
      return null;
    } on ApiException catch (e) {
      _busy = false;
      _lastError = e.code;
      _notify();
      if (e.statusCode == 422) return 'windowExpiredTitle';
      return e.isNetwork ? 'offline' : 'errServer';
    } catch (_) {
      _busy = false;
      _notify();
      return 'errServer';
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

/// Support tab-page.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, this.controller, this.orderContext, this.openUrl});

  final SupportController? controller;
  final String? orderContext; // prefilled wa.me text when opened from orders

  /// Opens [url] externally. Injectable for widget tests (defaults to
  /// url_launcher's external-application launch).
  final Future<bool> Function(Uri url, {LaunchMode mode})? openUrl;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  late final SupportController _c =
      widget.controller ?? SupportController(api: ApiClient(accessToken: null));

  @override
  void initState() {
    super.initState();
    if (widget.controller == null &&
        _c.status == ComplaintStatus.initial) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _c.load());
    }
  }

  Future<void> _openWhatsApp() async {
    // Phase 4 §4.5: launch primary (orders_controller pattern), clipboard
    // copy stays as the fallback — never the primary. Digits derive from
    // the single [kSupportPhone] constant (no second source of truth).
    final digits = kSupportPhone.replaceAll(RegExp(r'\D'), '');
    final text = widget.orderContext ??
        'Namaste! Mujhe paani ke order me madad chahiye.';
    final uri = Uri.parse(
      'https://wa.me/$digits?text=${Uri.encodeComponent(text)}',
    );
    final open = widget.openUrl ?? launchUrl;
    bool ok = false;
    try {
      ok = await open(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (ok || !mounted) return;
    // Copy runs unawaited: a slow/denied clipboard must never delay the
    // fallback message (and never strand it — the snackbar is the signal,
    // the copy is best-effort).
    unawaited(
      Clipboard.setData(ClipboardData(text: kSupportPhone)).then<void>(
        (_) {},
        onError: (_) {},
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(supportStringsHi['waFail']!)),
      );
    }
  }

  Future<void> _openComplaintForm() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (_) => _ComplaintFormSheet(controller: _c),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(supportStringsHi['title']!)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // WhatsApp primary entry (flat card, blue cue on the icon only).
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: ShodashaTheme.border),
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.chat_bubble_outline,
                  color: ShodashaTheme.blue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        supportStringsHi['waTitle']!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: ShodashaTheme.ink,
                        ),
                      ),
                      Text(
                        supportStringsHi['waSub']!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: ShodashaTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _openWhatsApp,
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            supportStringsHi['faqTitle']!,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const _Faq(
            q: 'Deposit kitna hai?',
            a: 'Rs 150 per jar — one time, refundable. Return par 10 din me wapas.',
          ),
          const _Faq(
            q: 'Delivery window kya hai?',
            a: '30-minute slot, subah 8 se raat 8 baje tak (Sunday band).',
          ),
          const _Faq(
            q: 'Khali jar kab wapas karein?',
            a: 'Jitni jar aayi, utni khali agle delivery par de dein. Cap bhi laga dein.',
          ),
          const _Faq(
            q: 'COD limit kya hai?',
            a: 'Rs 2,000 tak COD chalega. Usse bada order UPI se karein.',
          ),
          const SizedBox(height: 24),
          // Complaint entry — the 3-day window is enforced server-side;
          // expiry shows the WhatsApp path instead of a dead form.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: ShodashaTheme.border),
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.report_outlined,
                  color: ShodashaTheme.blue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        supportStringsHi['complaintTitle']!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: ShodashaTheme.ink,
                        ),
                      ),
                      Text(
                        supportStringsHi['complaintSub']!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: ShodashaTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _openComplaintForm,
                  child: const Text('Form'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            supportStringsHi['myComplaints']!,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: _c,
            builder: (context, _) {
              if (_c.status == ComplaintStatus.loading &&
                  _c.items.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              // Error branch (was: silent 'none') — message + retry.
              if (_c.status == ComplaintStatus.error && _c.items.isEmpty) {
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        _c.errorMessage ?? supportStringsHi['errServer']!,
                        style: const TextStyle(color: ShodashaTheme.muted),
                      ),
                    ),
                    TextButton(
                      onPressed: _c.load,
                      child: const Text('Dobara try karein'),
                    ),
                  ],
                );
              }
              if (_c.items.isEmpty) {
                return Text(
                  supportStringsHi['none']!,
                  style: const TextStyle(color: ShodashaTheme.muted),
                );
              }
              return Column(
                children: [
                  for (final cm in _c.items)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: ShodashaTheme.border),
                        borderRadius:
                            BorderRadius.circular(ShodashaTheme.radius),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  kComplaintReasonsHi[cm.reasonCode] ??
                                      cm.reasonCode,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '#${cm.orderId}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: ShodashaTheme.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            cm.status == 'resolved'
                                ? supportStringsHi['statusResolved']!
                                : cm.status == 'progress'
                                    ? supportStringsHi['statusProgress']!
                                    : supportStringsHi['statusOpen']!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cm.status == 'resolved'
                                  ? ShodashaTheme.success
                                  : ShodashaTheme.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One FAQ row (expand/collapse, hairline border, no accordion deps).
class _Faq extends StatefulWidget {
  const _Faq({required this.q, required this.a});

  final String q;
  final String a;

  @override
  State<_Faq> createState() => _FaqState();
}

class _FaqState extends State<_Faq> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.q,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: ShodashaTheme.ink,
                      ),
                    ),
                  ),
                  Icon(
                    _open
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: ShodashaTheme.muted,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text(
                widget.a,
                style: const TextStyle(
                  color: ShodashaTheme.muted,
                  fontSize: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Complaint form sheet: reason select (11 codes) + order + text ≤500.
/// No photo field (v1 contract). 24h/3d windows enforced server-side;
/// 422 → expiry dialog with WhatsApp fallback (never a silent removal).
class _ComplaintFormSheet extends StatefulWidget {
  const _ComplaintFormSheet({required this.controller});

  final SupportController controller;

  @override
  State<_ComplaintFormSheet> createState() => _ComplaintFormSheetState();
}

class _ComplaintFormSheetState extends State<_ComplaintFormSheet> {
  final _order = TextEditingController();
  final _text = TextEditingController();
  String _reason = 'water_quality';
  bool _touched = false;

  bool get _textOk =>
      _text.text.trim().length >= 10 && _text.text.trim().length <= 500;
  bool get _orderOk => _order.text.trim().isNotEmpty;
  bool get _valid => _textOk && _orderOk;

  @override
  void dispose() {
    _order.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _touched = true);
    if (!_valid) return;
    FocusScope.of(context).unfocus();
    final err = await widget.controller.submit(
      orderId: _order.text.trim(),
      reasonCode: _reason,
      text: _text.text.trim(),
    );
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(supportStringsHi['sent']!)),
      );
      return;
    }
    if (err == 'windowExpiredTitle') {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: ShodashaTheme.shape,
          title: Text(supportStringsHi['windowExpiredTitle']!),
          content: Text(supportStringsHi['windowExpiredBody']!),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Theek hai'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(supportStringsHi[err] ?? err)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  supportStringsHi['complaintTitle']!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _reason,
                  decoration: InputDecoration(
                    labelText: supportStringsHi['reasonLabel'],
                  ),
                  items: [
                    for (final e in kComplaintReasonsHi.entries)
                      DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value),
                      ),
                  ],
                  onChanged: (v) => setState(() => _reason = v ?? _reason),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _order,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: supportStringsHi['orderLabel'],
                    hintText: '#A3F9',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _text,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 500,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: supportStringsHi['textLabel'],
                    counterText: '',
                    errorText: _touched && !_textOk
                        ? supportStringsHi['textError']
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (c.busy || !_valid) ? null : _submit,
                    child: c.busy
                        ? Text(supportStringsHi['sending']!)
                        : Text(supportStringsHi['submit']!),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
