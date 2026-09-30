// F5 — Profile tab: identity + ledger card + return-jar + language + logout.
// ignore_for_file: prefer_initializing_formals
// WHY: public ctor param `api:` is the API (same pattern as F2 auth);
// private initializing formals are unusable from other libraries.
// Contract §4.1 (/auth/me, PATCH /auth/me), §4.6 (GET /ledger/me read-only
// held/deposit/dues; POST /returns → 10-working-day SLA + request id).
// Suspended users: read + pay-dues/appeal only (contract §4.1 restrictions
// surface as a banner; booking actions live on Home and stay gated).
// Language: Hindi default, English fallback — maps merge so no key is blank.

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

const Map<String, String> profileStringsHi = {
  'title': 'Profile',
  'loginToView': 'Login karke apna account dekhein',
  'ledgerTitle': 'Jar hisaab',
  'held': 'Aapke paas jar',
  'deposit': 'Deposit jama',
  'dues': 'Baki rashi',
  'returnTitle': 'Jar wapas karne ka request',
  'returnSub': '10 working days me pickup + refund',
  'returnQty': 'Kitni jar wapas karni hain?',
  'returnPick': 'Pickup address',
  'returnSend': 'Request bhejein',
  'returnSent': 'Request darj — 10 working days me pickup',
  'langTitle': 'Bhasha',
  'langHi': 'Hindi',
  'langEn': 'English',
  'subsLink': 'Subscriptions',
  'addrLink': 'Addresses',
  'logout': 'Logout',
  'logoutConfirmTitle': 'Logout karein?',
  'logoutConfirmBody': 'Order track karne ke liye dobara login karna hoga.',
  'logoutYes': 'Haan, logout',
  'logoutNo': 'Rehne dein',
  'errLedger': 'Hisaab load nahi hua',
  'offline': 'Internet nahi — dobara try karein',
  'errReturn': 'Request nahi gayi — dobara try karein',
  'suspendedBanner': 'Account suspended — dues chukane ya appeal ke alawa '
      'actions band hain. WhatsApp par appeal karein.',
};

/// English fallback map (Hindi default; merge guarantees no blank keys).
const Map<String, String> profileStringsEn = {
  'title': 'Profile',
  'loginToView': 'Log in to view your account',
  'ledgerTitle': 'Jar ledger',
  'held': 'Jars with you',
  'deposit': 'Deposit held',
  'dues': 'Dues',
  'returnTitle': 'Return jars request',
  'returnSub': 'Pickup + refund in 10 working days',
  'returnQty': 'How many jars to return?',
  'returnPick': 'Pickup address',
  'returnSend': 'Send request',
  'returnSent': 'Request filed — pickup within 10 working days',
  'langTitle': 'Language',
  'langHi': 'Hindi',
  'langEn': 'English',
  'subsLink': 'Subscriptions',
  'addrLink': 'Addresses',
  'logout': 'Log out',
  'logoutConfirmTitle': 'Log out?',
  'logoutConfirmBody': 'You will need to log in again to track orders.',
  'logoutYes': 'Yes, log out',
  'logoutNo': 'Stay',
  'errLedger': 'Could not load ledger',
  'offline': 'No internet — try again',
  'errReturn': 'Request failed — try again',
  'suspendedBanner': 'Account suspended — only dues payment and appeal '
      'remain available. Appeal via WhatsApp.',
};

/// v1 language toggle: Hindi default, English fallback (spec screen 11).
/// Merge order: Hindi wins when present, English fills gaps — never blank.
String profileText(String key, bool hindi) =>
    hindi ? (profileStringsHi[key] ?? profileStringsEn[key] ?? key)
        : (profileStringsEn[key] ?? profileStringsHi[key] ?? key);

enum LedgerStatus { initial, loading, loaded, error }

@immutable
class LedgerSnapshot {
  const LedgerSnapshot({
    this.heldJars = 0,
    this.depositPaise = 0,
    this.duesPaise = 0,
    this.suspended = false,
  });

  final int heldJars;
  final int depositPaise;
  final int duesPaise;
  final bool suspended;

  static LedgerSnapshot fromApi(Map<String, dynamic> j) => LedgerSnapshot(
        heldJars: (j['held_jars'] ?? j['d_held'] ?? 0) as int,
        depositPaise: (j['deposit_paise'] ?? j['d_deposit'] ?? 0) as int,
        duesPaise: (j['dues_paise'] ?? j['d_dues'] ?? 0) as int,
        suspended: (j['suspended'] ?? false) as bool,
      );
}

class ProfileController extends ChangeNotifier {
  ProfileController({required ApiClient api}) : _api = api;

  final ApiClient _api;

  LedgerStatus _status = LedgerStatus.initial;
  LedgerSnapshot _ledger = const LedgerSnapshot();
  String? _errorMessage;
  bool _busy = false;
  bool _hindi = true;

  LedgerStatus get status => _status;
  LedgerSnapshot get ledger => _ledger;
  String? get errorMessage => _errorMessage;
  bool get busy => _busy;
  bool get hindi => _hindi;

  set hindi(bool v) {
    _hindi = v;
    _notify();
  }

  String t(String key) => profileText(key, _hindi);

  Future<void> load() async {
    if (_status == LedgerStatus.loading) return;
    _status = LedgerStatus.loading;
    _errorMessage = null;
    _notify();
    try {
      _ledger = LedgerSnapshot.fromApi(await _api.ledgerMe());
      _status = LedgerStatus.loaded;
    } on ApiException catch (e) {
      _status = LedgerStatus.error;
      _errorMessage = e.isNetwork ? t('offline') : t('errLedger');
    } catch (_) {
      _status = LedgerStatus.error;
      _errorMessage = t('errLedger');
    }
    _notify();
  }

  /// POST /returns → request id + 10-working-day SLA. Returns error key or
  /// null on success (screen toasts + closes the sheet).
  Future<String?> requestReturn({
    required int qty,
    required String addressId,
  }) async {
    _busy = true;
    _notify();
    try {
      await _api.createReturn(qty: qty, addressId: addressId);
      return null;
    } on ApiException catch (e) {
      return e.isNetwork ? 'offline' : 'errReturn';
    } catch (_) {
      return 'errReturn';
    } finally {
      _busy = false;
      _notify();
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

/// Profile tab-page. Guest mode shows the login CTA (prices were never
/// walled, but account data is — contract flow 1).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.isAuthenticated,
    this.controller,
    this.onLoginRequired,
    this.onLogout,
    this.onOpenAddresses,
    this.onOpenSubscriptions,
  });

  final bool isAuthenticated;
  final ProfileController? controller;
  final VoidCallback? onLoginRequired;
  final VoidCallback? onLogout;
  final VoidCallback? onOpenAddresses;
  final VoidCallback? onOpenSubscriptions;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileController _c =
      widget.controller ?? ProfileController(api: ApiClient());

  @override
  void initState() {
    super.initState();
    if (widget.isAuthenticated &&
        widget.controller == null &&
        _c.status == LedgerStatus.initial) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _c.load());
    }
  }

  Future<void> _openReturnSheet() async {
    final err = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (_) => _ReturnSheet(controller: _c),
    );
    if (!mounted) return;
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_c.t('returnSent'))),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_c.t(err))),
      );
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: ShodashaTheme.shape,
        title: Text(_c.t('logoutConfirmTitle')),
        content: Text(_c.t('logoutConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_c.t('logoutNo')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_c.t('logoutYes')),
          ),
        ],
      ),
    );
    if (ok == true) widget.onLogout?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_c.t('title'))),
      body: !widget.isAuthenticated
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _c.t('loginToView'),
                    style: const TextStyle(
                      fontSize: 16,
                      color: ShodashaTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: widget.onLoginRequired,
                    child: const Text('Login'),
                  ),
                ],
              ),
            )
          : ListenableBuilder(
              listenable: _c,
              builder: (context, _) {
                final l = _c.ledger;
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (l.suspended)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: ShodashaTheme.danger),
                          borderRadius:
                              BorderRadius.circular(ShodashaTheme.radius),
                        ),
                        child: Text(
                          _c.t('suspendedBanner'),
                          style: const TextStyle(
                            color: ShodashaTheme.danger,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    // Ledger card (read-only per contract §4.6).
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: ShodashaTheme.border),
                        borderRadius:
                            BorderRadius.circular(ShodashaTheme.radius),
                      ),
                      child: _c.status == LedgerStatus.loading
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(8),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _c.t('ledgerTitle'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _LedgerRow(
                                  label: _c.t('held'),
                                  value: '${l.heldJars}',
                                ),
                                _LedgerRow(
                                  label: _c.t('deposit'),
                                  value: 'Rs ${l.depositPaise ~/ 100}',
                                ),
                                _LedgerRow(
                                  label: _c.t('dues'),
                                  value: 'Rs ${l.duesPaise ~/ 100}',
                                  highlight: l.duesPaise > 0,
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    // Return-jar request (10-day SLA text visible pre-tap).
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: ShodashaTheme.border),
                        borderRadius:
                            BorderRadius.circular(ShodashaTheme.radius),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.undo_outlined,
                            color: ShodashaTheme.blue,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _c.t('returnTitle'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  _c.t('returnSub'),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: ShodashaTheme.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _openReturnSheet,
                            child: const Text('Request'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.home_outlined,
                        color: ShodashaTheme.ink,
                      ),
                      title: Text(_c.t('addrLink')),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: ShodashaTheme.muted,
                      ),
                      onTap: widget.onOpenAddresses,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.repeat_outlined,
                        color: ShodashaTheme.ink,
                      ),
                      title: Text(_c.t('subsLink')),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: ShodashaTheme.muted,
                      ),
                      onTap: widget.onOpenSubscriptions,
                    ),
                    const Divider(),
                    // Language toggle (Hindi default, English fallback).
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_c.t('langTitle')),
                      subtitle: Text(
                        _c.hindi ? _c.t('langHi') : _c.t('langEn'),
                      ),
                      value: _c.hindi,
                      onChanged: (v) => _c.hindi = v,
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.logout,
                        color: ShodashaTheme.danger,
                      ),
                      title: Text(
                        _c.t('logout'),
                        style: const TextStyle(color: ShodashaTheme.danger),
                      ),
                      onTap: _confirmLogout,
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
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
              style: const TextStyle(
                color: ShodashaTheme.muted,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: highlight ? ShodashaTheme.danger : ShodashaTheme.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Return-jar sheet: qty stepper + pickup address id + landmark note.
class _ReturnSheet extends StatefulWidget {
  const _ReturnSheet({required this.controller});

  final ProfileController controller;

  @override
  State<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<_ReturnSheet> {
  final _address = TextEditingController();
  int _qty = 1;

  bool get _valid => _qty >= 1 && _address.text.trim().isNotEmpty;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    final err = await widget.controller.requestReturn(
      qty: _qty,
      addressId: _address.text.trim(),
    );
    if (!mounted) return;
    Navigator.of(context).pop(err); // null = success
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
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.t('returnTitle'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              Text(
                c.t('returnSub'),
                style: const TextStyle(
                  fontSize: 13,
                  color: ShodashaTheme.muted,
                ),
              ),
              const SizedBox(height: 14),
              Text(c.t('returnQty')),
              Row(
                children: [
                  IconButton.outlined(
                    onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      '$_qty',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton.outlined(
                    onPressed: _qty < 10 ? () => setState(() => _qty++) : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _address,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: c.t('returnPick'),
                  hintText: 'address id ya Home/Office',
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (c.busy || !_valid) ? null : _send,
                  child: c.busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(c.t('returnSend')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
