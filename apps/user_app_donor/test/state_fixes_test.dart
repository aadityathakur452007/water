import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/core/api_client.dart';
import 'package:shodasha_donor/features/addresses/address_screen.dart';
import 'package:shodasha_donor/features/orders/orders_controller.dart';
import 'package:shodasha_donor/features/profile/profile_controller.dart';
import 'package:shodasha_donor/features/returns/returns_controller.dart';
import 'package:shodasha_donor/features/wallet/wallet_controller.dart';

void main() {
  group('transport error split', () {
    test('only NETWORK is offline; 5xx is a server error', () {
      final offline = ApiException(
        code: 'NETWORK',
        message: 'socket',
        statusCode: 0,
      );
      final server = ApiException(
        code: 'INTERNAL',
        message: 'boom',
        statusCode: 503,
      );
      expect(offline.isOffline, isTrue);
      expect(offline.isServerError, isFalse);
      expect(server.isOffline, isFalse);
      expect(server.isServerError, isTrue);
    });
  });

  group('delivery code', () {
    test('parses active code and hides it once expired or used', () {
      final now = DateTime.utc(2026, 10, 23, 12);
      final active = orderFromApi({
        'id': 'o1',
        'state': 'dispatched',
        'window_start': now.toIso8601String(),
        'delivery_otp': '123456',
        'delivery_otp_expires_at': now
            .add(const Duration(hours: 1))
            .toIso8601String(),
        'delivery_otp_state': 'active',
        'delivery_otp_reissue_available': false,
      });
      expect(active.deliveryOtp, '123456');
      expect(active.deliveryCodeStateAt(now), 'active');
      expect(
        active.deliveryCodeStateAt(now.add(const Duration(hours: 2))),
        'expired',
      );

      final used = orderFromApi({
        'id': 'o2',
        'state': 'delivered',
        'window_start': now.toIso8601String(),
        'delivery_otp': '123456',
        'delivery_otp_state': 'used',
      });
      expect(used.deliveryOtp, isNull);
      expect(used.deliveryCodeState, 'used');
    });

    test('legacy payload without delivery fields is safe', () {
      final order = orderFromApi({
        'id': 'o3',
        'state': 'placed',
        'window_start': DateTime.utc(2026, 10, 23).toIso8601String(),
      });
      expect(order.deliveryOtp, isNull);
      expect(order.deliveryCodeState, 'none');
      expect(order.deliveryCodeReissueAvailable, isFalse);
    });

    test('controller reissues an expired code and updates the row', () async {
      final repo = StubOrdersRepository([
        orderFromApi({
          'id': 'o1',
          'state': 'dispatched',
          'window_start': DateTime.utc(2026, 10, 23).toIso8601String(),
          'delivery_otp_state': 'expired',
          'delivery_otp_reissue_available': true,
        }),
      ]);
      final controller = OrdersController(repo: repo);
      addTearDown(controller.dispose);
      await controller.load();

      final result = await controller.reissueDeliveryCode('o1');

      expect(result.ok, isTrue);
      expect(controller.findById('o1')?.deliveryOtp, '654321');
      expect(controller.findById('o1')?.deliveryCodeState, 'active');
      expect(controller.reissueBusy, isFalse);

      final again = await controller.reissueDeliveryCode('o1');
      expect(again.ok, isFalse);
      expect(again.message, contains('still active'));
    });

    test(
      'detail refresh keeps the stale row and flags transport vs 5xx',
      () async {
        final seed = orderFromApi({
          'id': 'o1',
          'state': 'dispatched',
          'window_start': DateTime.utc(2026, 10, 23).toIso8601String(),
        });
        final offline = OrdersController(
          repo: _DetailErrorRepo([
            seed,
          ], ApiException(code: 'NETWORK', message: 'socket', statusCode: 0)),
        );
        addTearDown(offline.dispose);
        await offline.load();
        await offline.refreshOrder('o1');
        expect(offline.findById('o1'), isNotNull);
        expect(offline.detailFailed, isTrue);
        expect(offline.detailOffline, isTrue);
        expect(offline.detailServerError, isFalse);

        final server = OrdersController(
          repo: _DetailErrorRepo([
            seed,
          ], ApiException(code: 'INTERNAL', message: 'boom', statusCode: 503)),
        );
        addTearDown(server.dispose);
        await server.load();
        await server.refreshOrder('o1');
        expect(server.detailFailed, isTrue);
        expect(server.detailOffline, isFalse);
        expect(server.detailServerError, isTrue);
      },
    );
  });

  group('profile validation', () {
    test('mobile is required and normalizes variants', () {
      expect(validateProfilePhone(''), contains('required'));
      expect(validateProfilePhone('+91 98765 43210'), isNull);
      expect(validateProfilePhone('09876543210'), isNull);
      expect(validateProfilePhone('12345'), isNotNull);
    });

    test('email is optional and any valid provider is accepted', () {
      expect(validateProfileEmail(''), isNull);
      expect(validateProfileEmail('asha@example.com'), isNull);
      expect(validateProfileEmail('asha@gmail.com'), isNull);
      expect(validateProfileEmail('asha@gmail'), isNotNull);
    });

    test('name is required and length-bounded', () {
      expect(validateProfileName('  '), isNotNull);
      expect(validateProfileName('Asha'), isNull);
      expect(validateProfileName('a' * 101), isNotNull);
    });
  });

  test('address phone is optional but normalized when supplied', () {
    expect(isValidOptionalPhone(''), isTrue);
    expect(isValidOptionalPhone('+91 98765 43210'), isTrue);
    expect(isValidOptionalPhone('09876543210'), isTrue);
    expect(isValidOptionalPhone('12345'), isFalse);
  });

  group('wallet', () {
    test('all-zero ledger is the honest empty state', () {
      final empty = LedgerSnapshot.fromApi({
        'held': 0,
        'deposit_paid': 0,
        'deposit_refunded': 0,
        'wallet_held': 0,
        'dues': 0,
      });
      expect(empty.isEmpty, isTrue);

      final dues = LedgerSnapshot.fromApi({'dues': 100});
      expect(dues.isEmpty, isFalse);
    });

    test('5xx is a server problem, not offline', () async {
      final controller = WalletController(
        api: _WalletApi(
          error: ApiException(
            code: 'INTERNAL',
            message: 'boom',
            statusCode: 500,
          ),
        ),
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.status, WalletStatus.error);
      expect(controller.errorMessage, 'Server problem — try again');
    });
  });

  group('returns', () {
    test('success keeps the server id, SLA and refund', () async {
      final controller = ReturnsController(
        api: _ReturnApi(
          result: {
            'id': 'ret_1',
            'status': 'requested',
            'qty': 2,
            'sla_due': '2026-11-06',
            'message': 'Return requested.',
            'refund_paise': 30000,
          },
        ),
      );
      addTearDown(controller.dispose);

      final ok = await controller.submit(qty: 2, addressId: 'addr_1');

      expect(ok, isTrue);
      expect(controller.lastRequest?.id, 'ret_1');
      expect(controller.lastRequest?.slaDue, '2026-11-06');
      expect(controller.lastRequest?.refundPaise, 30000);
      expect(controller.isAuthError, isFalse);
    });

    test('401 exposes the sign-in action state', () async {
      final controller = ReturnsController(
        api: _ReturnApi(
          error: ApiException(
            code: 'UNAUTH',
            message: 'expired',
            statusCode: 401,
          ),
        ),
      );
      addTearDown(controller.dispose);

      final ok = await controller.submit(qty: 1, addressId: 'addr_1');

      expect(ok, isFalse);
      expect(controller.isAuthError, isTrue);
      expect(controller.error, contains('log in again'));
    });
  });
}

class _DetailErrorRepo extends StubOrdersRepository {
  _DetailErrorRepo(super.seed, this.error);

  final ApiException error;

  @override
  Future<Order> fetchOrder(String id) async => throw error;
}

class _WalletApi extends ApiClient {
  _WalletApi({this.error}) : super(baseUrl: 'http://127.0.0.1/v1');

  final Object? error;

  @override
  Future<Map<String, dynamic>> ledgerMe() async {
    if (error != null) throw error!;
    return const {};
  }
}

class _ReturnApi extends ApiClient {
  _ReturnApi({this.result, this.error}) : super(baseUrl: 'http://127.0.0.1/v1');

  final Map<String, dynamic>? result;
  final Object? error;

  @override
  Future<Map<String, dynamic>> createReturn({
    required int qty,
    required String addressId,
    String? upiId,
  }) async {
    if (error != null) throw error!;
    return result ?? const {};
  }
}
