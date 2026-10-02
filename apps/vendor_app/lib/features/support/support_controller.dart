// Support: complaint verify (agree/disagree) + quality door check
// (seal/smell/visual). Quantity/deposit/cap disputes resolve from system
// records; quality needs the door check. v1 words, no photos.

// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';

class SupportController extends ChangeNotifier {
  SupportController({required ApiClient api}) : _api = api;

  final ApiClient _api;

  bool _submitting = false;
  String? _notice;

  bool get submitting => _submitting;
  String? get notice => _notice;

  /// Vendor complaint queue (011_port ticket-thread reads; verify writes).
  List<Map<String, dynamic>> _queue = const [];
  bool _queueLoading = false;
  String? _queueError;

  List<Map<String, dynamic>> get queue => _queue;
  bool get queueLoading => _queueLoading;
  String? get queueError => _queueError;

  Future<void> loadQueue() async {
    _queueLoading = true;
    _queueError = null;
    notifyListeners();
    try {
      final raw = await _api.vendorComplaints();
      _queue = ((raw['data'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
    } on ApiException catch (e) {
      // S5: surface instead of swallowing — verify-by-id below keeps working.
      _queue = const [];
      _queueError =
          e.isNetwork ? 'Network nahi — dobara try karein' : 'Queue load nahi hui';
    } finally {
      _queueLoading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyComplaint({
    required String complaintId,
    required bool agree,
    required String note,
  }) async {
    _submitting = true;
    _notice = null;
    notifyListeners();
    try {
      await _api.verifyComplaint(
          complaintId: complaintId, agree: agree, note: note);
      _notice = agree
          ? 'Sahmat — redelivery/refund jaari'
          : 'Asahmat — admin review me (48h)';
      return true;
    } on ApiException catch (e) {
      _notice = e.isNetwork ? 'Network nahi — dobara try karein' : e.message;
      return false;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  Future<bool> checkQuality({
    required String incidentId,
    required bool agree,
    required String check,
    required String note,
  }) async {
    _submitting = true;
    _notice = null;
    notifyListeners();
    try {
      await _api.vendorCheckQuality(
          incidentId: incidentId, agree: agree, check: check, note: note);
      _notice = agree ? 'Confirm — redelivery/refund jaari' : 'Vivaad — admin faisla karega';
      return true;
    } on ApiException catch (e) {
      _notice = e.isNetwork ? 'Network nahi — dobara try karein' : e.message;
      return false;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  void clearNotice() {
    _notice = null;
    notifyListeners();
  }
}
