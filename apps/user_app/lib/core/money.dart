// Money display — the ONE rupee formatter (P1-12).
//
// The backend sends integer paise everywhere; the client never derives money.
// 2dp appears only when the amount has paise (5600 → ₹56, 5650 → ₹56.50,
// 5 → ₹0.05). Negative amounts keep the sign outside the symbol.

/// Formats server paise as Indian rupees for display only.
String formatInr(int paise) {
  final sign = paise < 0 ? '-' : '';
  final abs = paise.abs();
  if (abs % 100 == 0) return '$sign\u20B9${abs ~/ 100}';
  return '$sign\u20B9${(abs / 100).toStringAsFixed(2)}';
}
