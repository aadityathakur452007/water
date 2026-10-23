// S8 — Support complaints: GET /v1/complaints + POST /v1/complaints.
//
// States.md coverage: loading (skeleton), loaded, empty ("no complaints"),
// error (message + retry), submitting (button label), success (sheet pops +
// snackbar), client validation (10–500 chars), server 422 (complaint window
// closed → WhatsApp path), offline, unauthorized.
//
// The authenticated ApiClient is ALWAYS injected (ADR-118): no
// unauthenticated fallback and no 'unknown-device' identity split.

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';

/// Copy used by the controller and the screen (English v1, ADR-120).
const Map<String, String> supportStrings = {
  'loadError': 'Could not load your complaints.',
  'offline': 'No internet — please try again.',
  'server': 'Server problem — retry in a moment.',
  'sessionExpired': 'Session expired. Log in again to see your complaints.',
  'sendError': 'Could not send your complaint — please try again.',
};

/// The 11 contract reason codes (schema `complaints.reason_code`) in English.
const Map<String, String> kComplaintReasonLabels = {
  'water_quality': 'Water quality',
  'damaged_jar': 'Damaged or leaking jar',
  'wrong_item': 'Wrong item delivered',
  'short_delivery': 'Fewer jars delivered',
  'late_delivery': 'Late delivery',
  'deposit_dispute': 'Deposit dispute',
  'cap_dispute': 'Cap charge',
  'duplicate_app_order': 'Duplicate order',
  'not_needed_today': 'Not needed today',
  'vendor_behavior': 'Rider behaviour',
  'other': 'Something else',
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

  /// Server status: open | progress | resolved (tolerant to in_progress).
  final String status;
  final String? createdAt;

  static ComplaintEntry fromApi(Map<String, dynamic> json) => ComplaintEntry(
    id: (json['id'] ?? '') as String,
    orderId: (json['order_id'] ?? '') as String,
    reasonCode: (json['reason_code'] ?? 'other') as String,
    text: (json['text'] ?? '') as String,
    status: (json['status'] ?? 'open') as String,
    createdAt: json['created_at'] as String?,
  );
}

class SupportController extends ChangeNotifier {
  // ignore: prefer_initializing_formals — public ctor name is the API seam.
  SupportController({required ApiClient api}) : _api = api;

  final ApiClient _api;

  ComplaintStatus _status = ComplaintStatus.initial;
  List<ComplaintEntry> _items = [];
  String? _errorMessage;
  bool _busy = false;
  String? _lastError;
  bool _disposed = false;

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
      await _refreshItems();
      _status = ComplaintStatus.loaded;
    } on ApiException catch (e) {
      _status = ComplaintStatus.error;
      _errorMessage = _loadError(e);
    } catch (_) {
      _status = ComplaintStatus.error;
      _errorMessage = supportStrings['loadError'];
    }
    _notify();
  }

  /// POST /complaints. Returns an error key ('offline' | 'sendError' |
  /// 'windowExpired') or null on success. Server 422 → the caller shows the
  /// WhatsApp help path, never a silent drop.
  Future<String?> submit({
    required String orderId,
    required String reasonCode,
    required String text,
  }) async {
    if (_busy) return null;
    _busy = true;
    _lastError = null;
    _notify();
    try {
      await _api.createComplaint(
        orderId: orderId,
        reasonCode: reasonCode,
        text: text,
      );
      // The complaint is filed; refreshing the list is best-effort so a
      // read hiccup can never turn a success into a failure toast.
      try {
        await _refreshItems();
        _status = ComplaintStatus.loaded;
      } catch (_) {
        // Keep whatever the list already shows.
      }
      return null;
    } on ApiException catch (e) {
      _lastError = e.code;
      if (e.statusCode == 422) return 'windowExpired';
      if (e.isServerError) return 'server';
      return e.code == 'NETWORK' ? 'offline' : supportStrings['sendError'];
    } catch (_) {
      return supportStrings['sendError'];
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> _refreshItems() async {
    final raw = await _api.listComplaints();
    _items = raw
        .whereType<Map<String, dynamic>>()
        .map(ComplaintEntry.fromApi)
        .toList();
  }

  String _loadError(ApiException e) {
    if (e.code == 'NETWORK') return supportStrings['offline']!;
    if (e.isServerError) return supportStrings['server']!;
    if (e.statusCode == 401 || e.statusCode == 403) {
      return supportStrings['sessionExpired']!;
    }
    return supportStrings['loadError']!;
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
