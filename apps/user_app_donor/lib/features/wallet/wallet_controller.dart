// S7 — wallet ledger state, fed only by GET /v1/ledger/me.
//
// States.md coverage: loading (skeleton in wallet_screen), loaded (hero +
// statement), empty (a real all-zero server snapshot — never a placeholder
// hero), error (message + retry), guest (login CTA, zero network). [ledger]
// stays null until the server answers, so a fake ₹0 hero can never flash.

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';

enum WalletStatus { initial, loading, loaded, error }

@immutable
class LedgerSnapshot {
  const LedgerSnapshot({
    required this.heldJars,
    required this.depositPaidPaise,
    required this.depositRefundedPaise,
    required this.depositHeldPaise,
    required this.duesPaise,
  });

  /// Jars currently with the customer (server `held`).
  final int heldJars;

  /// Lifetime deposit paid (server `deposit_paid`, paise).
  final int depositPaidPaise;

  /// Lifetime deposit already refunded (server `deposit_refunded`, paise).
  final int depositRefundedPaise;

  /// Refundable deposit still held (server `wallet_held`, paise).
  final int depositHeldPaise;

  /// Outstanding dues (server `dues`, paise).
  final int duesPaise;

  /// Nothing outstanding on the jar account. This is the server's answer —
  /// the screen swaps the hero for an honest empty state, never a ₹0 hero.
  bool get isEmpty => heldJars == 0 && depositHeldPaise == 0 && duesPaise == 0;

  /// GET /v1/ledger/me:
  /// `{held, deposit_paid, deposit_refunded, wallet_held, dues}`.
  /// Legacy aliases stay tolerated so older fixtures keep parsing.
  static LedgerSnapshot fromApi(Map<String, dynamic> j) => LedgerSnapshot(
    heldJars: _int(j['held'] ?? j['held_jars'] ?? j['d_held']),
    depositPaidPaise: _int(j['deposit_paid'] ?? j['deposit_paise']),
    depositRefundedPaise: _int(j['deposit_refunded']),
    depositHeldPaise: _int(
      j['wallet_held'] ?? j['deposit_paise'] ?? j['d_deposit'],
    ),
    duesPaise: _int(j['dues'] ?? j['dues_paise'] ?? j['d_dues']),
  );
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

class WalletController extends ChangeNotifier {
  WalletController({required this.api});

  final ApiClient api;

  WalletStatus _status = WalletStatus.initial;
  LedgerSnapshot? _ledger;
  String? _errorMessage;
  bool _refreshing = false;
  bool _stale = false;
  bool _isOffline = false;
  bool _isServerError = false;
  bool _disposed = false;

  WalletStatus get status => _status;
  LedgerSnapshot? get ledger => _ledger;
  String? get errorMessage => _errorMessage;
  bool get isRefreshing => _refreshing;

  /// True when a refresh failed but the previous ledger is still on screen.
  bool get isStale => _stale;
  bool get isOffline => _isOffline;
  bool get isServerError => _isServerError;

  /// Single-flight: a second call while loading joins the first. A failed
  /// refresh keeps the last good ledger visible and marks it stale.
  Future<void> load() async {
    if (_refreshing) return;
    _refreshing = true;
    _errorMessage = null;
    if (_ledger == null) _status = WalletStatus.loading;
    _notify();
    try {
      _ledger = LedgerSnapshot.fromApi(await api.ledgerMe());
      _status = WalletStatus.loaded;
      _stale = false;
      _isOffline = false;
      _isServerError = false;
    } on ApiException catch (e) {
      _isOffline = e.isOffline;
      _isServerError = e.isServerError;
      _errorMessage = e.isOffline
          ? 'No internet — try again'
          : e.isServerError
          ? 'Server problem — try again'
          : 'Could not load your ledger';
      if (_ledger == null) {
        _status = WalletStatus.error;
      } else {
        _status = WalletStatus.loaded;
        _stale = true;
      }
    } catch (_) {
      _isOffline = false;
      _isServerError = false;
      _errorMessage = 'Could not load your ledger';
      if (_ledger == null) {
        _status = WalletStatus.error;
      } else {
        _status = WalletStatus.loaded;
        _stale = true;
      }
    } finally {
      _refreshing = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
