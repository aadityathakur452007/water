import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendor_app/core/api_client.dart';
import 'package:vendor_app/features/sync/sync_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncController terminal conflict quarantine & cash preservation', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('STALE_STOP is quarantined from queue, preventing infinite replay', () async {
      int syncAttempts = 0;
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/vendor/sync')) {
          syncAttempts++;
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final items = (body['items'] as List).cast<Map<String, dynamic>>();

          // Verify items in the batch request
          final stopIds = items.map((i) => i['stop_id']).toList();
          if (syncAttempts == 1) {
            expect(stopIds, containsAll(['stop_stale', 'stop_ok']));
            return http.Response(
              jsonEncode({
                'applied': ['stop_ok'],
                'replayed': [],
                'rejected': [
                  {
                    'stop_id': 'stop_stale',
                    'code': 'STALE_STOP',
                    'message': 'Stop was reassigned. Pull fresh route.',
                  }
                ],
              }),
              200,
            );
          } else {
            // In attempt 2, the quarantined stop must NOT be sent again
            expect(stopIds, isEmpty);
            return http.Response(
              jsonEncode({'applied': [], 'replayed': [], 'rejected': []}),
              200,
            );
          }
        }
        return http.Response('Not Found', 404);
      });

      final controller = SyncController(api: ApiClient(client: mock, deviceId: 'test_dev'));
      await controller.load();

      // Enqueue two stops: one that will succeed, one that will 409
      await controller.enqueue(
        stopId: 'stop_stale',
        triple: {'version': 1, 'fulls_given': 1, 'empties_back': 1},
        cashAmountPaise: 8000, // Rs 80 collected offline
      );
      await controller.enqueue(
        stopId: 'stop_ok',
        triple: {'version': 1, 'fulls_given': 2, 'empties_back': 2},
        cashAmountPaise: 0,
      );

      expect(controller.queue.length, 2);

      // First sync: stop_ok applied, stop_stale rejected with STALE_STOP
      await controller.syncNow();
      expect(syncAttempts, 1);
      expect(controller.queue, isEmpty); // Both left active queue: ok applied, stale quarantined
      expect(controller.rejected, hasLength(1));

      // Check cash custody preservation in rejected record
      final rejectedRecord = controller.rejected.first;
      expect(rejectedRecord['stop_id'], 'stop_stale');
      expect(rejectedRecord['code'], 'STALE_STOP');
      expect(rejectedRecord['cash_amount'], 8000);
      expect(rejectedRecord['cash_warning'], contains('80 cash collected offline'));

      // Second sync: queue is empty, so syncNow does not make redundant network calls
      await controller.syncNow();
      expect(syncAttempts, 1); // No new request made

      // Discarding the rejected item clears it
      await controller.discardRejected('stop_stale');
      expect(controller.rejected, isEmpty);
      controller.dispose();
    });

    test('rejection and queue persist across controller reloads', () async {
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/vendor/sync')) {
          return http.Response(
            jsonEncode({
              'applied': [],
              'replayed': [],
              'rejected': [
                {
                  'stop_id': 'stop_conflict',
                  'code': 'ALREADY_COMPLETED',
                  'message': 'Stop already closed.',
                }
              ],
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final c1 = SyncController(api: ApiClient(client: mock, deviceId: 'test_dev'));
      await c1.load();
      await c1.enqueue(
        stopId: 'stop_conflict',
        triple: {'version': 2},
        cashAmountPaise: 16000,
      );
      await c1.syncNow();
      expect(c1.rejected, hasLength(1));
      expect(c1.queue, isEmpty);

      // Spin up new controller instance simulating app reboot
      final c2 = SyncController(api: ApiClient(client: mock, deviceId: 'test_dev'));
      await c2.load();
      expect(c2.queue, isEmpty);
      expect(c2.rejected, hasLength(1));
      expect(c2.rejected.first['stop_id'], 'stop_conflict');
      expect(c2.rejected.first['cash_amount'], 16000);

      await c2.clearAll();
      expect(c2.rejected, isEmpty);
      c1.dispose();
      c2.dispose();
    });
  });
}
