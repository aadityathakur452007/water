// S7 — jar-return submission state (POST /v1/returns).
//
// The request body is exactly {qty, address_id, upi_id}; the SLA and request
// id come back from the server. A refund amount is only surfaced when the
// server includes one (e.g. an admin-refunded history row) — this client never
// multiplies jars by a deposit rate.

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';

@immutable
class ReturnRequest {
  const ReturnRequest({
    required this.id,
    required this.status,
    required this.qty,
    required this.slaDue,
    required this.message,
    required this.refundPaise,
  });

  final String id;
  final String status;
  final int qty;
  final String slaDue;
  final String message;

  /// Server-stated refund (paise) when present — never client-computed.
  final int? refundPaise;

  static ReturnRequest fromApi(Map<String, dynamic> j) => ReturnRequest(
    id: (j['id'] ?? '').toString(),
    status: (j['status'] ?? 'requested').toString(),
    qty: _int(j['qty']),
    slaDue: (j['sla_due'] ?? '').toString(),
    message: (j['message'] ?? '').toString(),
    refundPaise: _intOrNull(
      j['refund_paise'] ?? j['refunded'] ?? j['refund_amount_paise'],
    ),
  );
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
int? _intOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

class ReturnsController extends ChangeNotifier {
  ReturnsController({required this.api});

  final ApiClient api;

  bool _busy = false;
  String? _error;
  ReturnRequest? _lastRequest;
  bool _disposed = false;

  bool get busy => _busy;
  String? get error => _error;
  ReturnRequest? get lastRequest => _lastRequest;

  /// Returns true on 2xx. Validation and transport failures land in [error]
  /// so the sheet can stay open with the user's inputs intact (States.md:
  /// submission failed → retry, never a dead end).
  Future<bool> submit({
    required int qty,
    required String addressId,
    String? upiId,
  }) async {
    if (_busy) return false;
    if (qty < 1 || qty > 30 || addressId.trim().isEmpty) {
      _error = 'Choose a pickup address and at least one jar';
      _notify();
      return false;
    }
    _busy = true;
    _error = null;
    _notify();
    try {
      final res = await api.createReturn(
        qty: qty,
        addressId: addressId.trim(),
        upiId: upiId?.trim(),
      );
      _lastRequest = ReturnRequest.fromApi(res);
      return true;
    } on ApiException catch (e) {
      _error = (e.statusCode == 401 || e.statusCode == 403)
          ? 'Session expired — log in again'
          : (e.isNetwork
                ? 'No internet — try again'
                : 'Request failed — try again');
      return false;
    } catch (_) {
      _error = 'Request failed — try again';
      return false;
    } finally {
      _busy = false;
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
