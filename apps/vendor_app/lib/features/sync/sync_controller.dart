// Offline outbox: queued triples persist in SharedPreferences and replay
// through POST /vendor/sync with per-stop idempotency keys. Server-wins on
// ledger; stale entries surface individually, never fail the batch.

// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../stops/stops_controller.dart';

@immutable
class QueuedTriple {
  const QueuedTriple({
    required this.stopId,
    required this.triple,
    required this.idempotencyKey,
    required this.queuedAtIso,
  });

  final String stopId;
  final Map<String, dynamic> triple;
  final String idempotencyKey;
  final String queuedAtIso;

  Map<String, dynamic> toJson() => {
        'stop_id': stopId,
        'triple': triple,
        'idempotency_key': idempotencyKey,
        'queued_at': queuedAtIso,
      };

  static QueuedTriple fromJson(Map<String, dynamic> j) => QueuedTriple(
        stopId: (j['stop_id'] ?? '') as String,
        triple: Map<String, dynamic>.from((j['triple'] ?? {}) as Map),
        idempotencyKey: (j['idempotency_key'] ?? '') as String,
        queuedAtIso: (j['queued_at'] ?? '') as String,
      );

  Map<String, dynamic> toSyncItem() => {
        'stop_id': stopId,
        'idempotency_key': idempotencyKey,
        ...triple,
      };
}

class SyncController extends ChangeNotifier {
  SyncController({required ApiClient api}) : _api = api;

  static const storageKey = 'vendor.outbox.v1';

  final ApiClient _api;

  List<QueuedTriple> _queue = const [];
  bool _syncing = false;
  String? _result;
  List<Map<String, dynamic>> _rejected = const [];

  List<QueuedTriple> get queue => _queue;
  bool get syncing => _syncing;
  String? get result => _result;
  List<Map<String, dynamic>> get rejected => _rejected;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      _queue = const [];
    } else {
      try {
        final list = jsonDecode(raw) as List;
        _queue = list
            .whereType<Map<String, dynamic>>()
            .map(QueuedTriple.fromJson)
            .toList();
      } catch (_) {
        _queue = const [];
      }
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        storageKey, jsonEncode(_queue.map((q) => q.toJson()).toList()));
  }

  /// Drops the whole outbox (logout path: the next login must never inherit
  /// another vendor's stops + cash amounts on a shared device).
  Future<void> clearAll() async {
    _queue = const [];
    _rejected = const [];
    _result = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
    notifyListeners();
  }

  Future<void> enqueue({
    required String stopId,
    required Map<String, dynamic> triple,
    String? idempotencyKey,
  }) async {
    _queue = [
      ..._queue,
      QueuedTriple(
        stopId: stopId,
        triple: triple,
        idempotencyKey: idempotencyKey ?? newIdempotencyKey(),
        queuedAtIso: DateTime.now().toIso8601String(),
      ),
    ];
    await _persist();
    notifyListeners();
  }

  /// Replays the queue. Applied/replayed ids leave the queue; rejected stay
  /// listed with their server code (STALE_STOP → pull fresh route first).
  Future<void> syncNow() async {
    if (_syncing || _queue.isEmpty) return;
    _syncing = true;
    _result = null;
    notifyListeners();
    try {
      final raw = await _api
          .syncBatch(_queue.map((q) => q.toSyncItem()).toList());
      final applied = ((raw['applied'] as List?) ?? const []).toSet();
      final replayed = ((raw['replayed'] as List?) ?? const []).toSet();
      final done = {...applied, ...replayed};
      _rejected = ((raw['rejected'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final rejectedIds =
          _rejected.map((r) => r['stop_id']).toSet();
      _queue = _queue
          .where((q) =>
              !done.contains(q.stopId) || rejectedIds.contains(q.stopId))
          .toList();
      await _persist();
      _result =
          '${done.length} synced • ${_rejected.length} rejected • ${_queue.length} baaki';
    } on ApiException catch (e) {
      _result = e.isNetwork
          ? 'Network nahi — baad me retry karein'
          : 'Sync fail: ${e.message}';
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  void clearResult() {
    _result = null;
    notifyListeners();
  }
}
