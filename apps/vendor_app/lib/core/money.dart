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

/// Deposit due at handover display: max(0, N - E) × 150 Rs (spec: Rs 150/jar).
int depositDueRs(int jarsOrdered, int emptiesDeclared) {
  final short = jarsOrdered - emptiesDeclared;
  return (short > 0 ? short : 0) * 150;
}

/// Cap-missing charge display: M × Rs 3.
int capChargeRs(int capsMissing) => capsMissing * 3;
