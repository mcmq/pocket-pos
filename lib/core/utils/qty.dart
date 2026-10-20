/// Formats a quantity: `2`, `1.5`, `0.125` (no trailing zeros).
String formatQty(double qty) {
  if (qty == qty.roundToDouble()) return qty.toStringAsFixed(0);
  return qty.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}
