// Money: integer paise on the wire, display-only Rs formatting.
// Server computes all money; the app never does money math beyond display.

/// 8600 → `Rs 86`; 15000 → `Rs 150`. Negative (shouldn't happen) keeps `-`.
String rupees(int paise) {
  final neg = paise < 0;
  final abs = paise.abs();
  final whole = abs ~/ 100;
  final frac = abs % 100;
  final body = frac == 0 ? '$whole' : '$whole.${frac.toString().padLeft(2, '0')}';
  return '${neg ? '-' : ''}Rs $body';
}

/// 015 deposit display: container-only once-only (server truth).
/// Repeat containers show Rs 0 — server waives when wallet holds deposit.
int depositDueRs(int containersOrdered, int emptiesDeclared, {bool walletHoldsDeposit = false}) {
  if (containersOrdered <= 0 || walletHoldsDeposit) return 0;
  final short = containersOrdered - emptiesDeclared.clamp(0, containersOrdered);
  return (short > 0 ? short : 0) * 150;
}

/// Cap-missing charge display: M × Rs 3.
int capChargeRs(int capsMissing) => capsMissing * 3;
