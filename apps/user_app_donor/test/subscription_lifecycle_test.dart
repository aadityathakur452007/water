import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/features/subscriptions/subscription_controller.dart';

void main() {
  group('SubscriptionLifecycle precedence and state machine resolution', () {
    test('resolves active when normal healthy plan', () {
      final entry = SubscriptionEntry.fromApi({
        'id': 'sub_1',
        'status': 'active',
        'billing_mode': 'per_delivery',
        'payment_method': 'cod',
      });
      expect(entry.lifecycle, SubscriptionLifecycle.active);
    });

    test('canceled has highest precedence over paused, awaitingPayment, and lowBalance', () {
      final entry = SubscriptionEntry.fromApi({
        'id': 'sub_2',
        'status': 'canceled',
        'canceled_at': '2026-11-18T00:00:00Z',
        'hold_from': '2026-11-20',
        'hold_to': '2026-11-25',
        'billing_mode': 'monthly_prepaid',
        'billing_status': 'pending_payment',
        'low_balance': true,
      });
      expect(entry.lifecycle, SubscriptionLifecycle.canceled);
    });

    test('paused has precedence over awaitingPayment and lowBalance', () {
      final entry = SubscriptionEntry.fromApi({
        'id': 'sub_3',
        'status': 'paused',
        'hold_from': '2026-11-20',
        'hold_to': '2026-11-25',
        'billing_mode': 'monthly_prepaid',
        'billing_status': 'pending_payment',
        'low_balance': true,
      });
      expect(entry.lifecycle, SubscriptionLifecycle.paused);
    });

    test('awaitingPayment has precedence over lowBalance for prepaid onboarding', () {
      final entry = SubscriptionEntry.fromApi({
        'id': 'sub_4',
        'status': 'active',
        'billing_mode': 'monthly_prepaid',
        'billing_status': 'pending_payment',
        'low_balance': true,
        'credit_balance_paise': 0,
      });
      expect(entry.lifecycle, SubscriptionLifecycle.awaitingPayment);
    });

    test('lowBalance resolves when active prepaid with balance deficit', () {
      final entry = SubscriptionEntry.fromApi({
        'id': 'sub_5',
        'status': 'active',
        'billing_mode': 'monthly_prepaid',
        'billing_status': 'active',
        'low_balance': true,
        'credit_balance_paise': 2000,
      });
      expect(entry.lifecycle, SubscriptionLifecycle.lowBalance);
    });

    test('active resolves when prepaid has active billing and healthy balance', () {
      final entry = SubscriptionEntry.fromApi({
        'id': 'sub_6',
        'status': 'active',
        'billing_mode': 'monthly_prepaid',
        'billing_status': 'active',
        'low_balance': false,
        'credit_balance_paise': 150000,
      });
      expect(entry.lifecycle, SubscriptionLifecycle.active);
    });
  });
}
