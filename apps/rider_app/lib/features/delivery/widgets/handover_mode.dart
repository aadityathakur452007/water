part of 'pod_sheet.dart';

enum HandoverMode {
  /// Daily subscription refill: ₹0 due, do not collect daily cash
  dailySubscription,

  /// Subscription month-end dues: cash collection required for accumulated dues
  monthEndDues,

  /// One-time Cash on Delivery: cash collection required for order total
  standardCod,

  /// Prepaid (UPI confirmed or ₹0 due): no doorstep cash collection
  prepaid,
}

/// Pure resolution function for Doorstep Handover Mode.
HandoverMode resolveHandoverMode(Map<String, dynamic> stop) {
  final isSub = stop['is_subscription'] == true;
  final isMonthlyDues = stop['is_monthly_dues'] == true;
  final isCod = stop['payment_mode'] == 'cod';
  final amountDue = (stop['amount_due'] as num?)?.toInt() ?? 0;
  final paymentStatus = stop['payment_status']?.toString() ?? '';
  final isPaid = paymentStatus == 'paid_upi' || paymentStatus == 'paid_cash';

  if (isSub && !isMonthlyDues) {
    return HandoverMode.dailySubscription;
  }
  if (isMonthlyDues && amountDue > 0) {
    return HandoverMode.monthEndDues;
  }
  if (!isSub && isCod && amountDue > 0) {
    return HandoverMode.standardCod;
  }
  if (isPaid || amountDue == 0) {
    return HandoverMode.prepaid;
  }
  return HandoverMode.standardCod;
}

