import 'package:intl/intl.dart';

/// Where the currency symbol goes relative to the number.
enum SymbolPosition { start, end }

/// Digit grouping style: `1,000,000` (western) or `10,00,000` (indian).
enum NumberGrouping { western, indian }

/// Formats and parses money held as **integer minor units** (e.g. cents).
///
/// Money is never a `double` in PocketPOS. Doubles appear only transiently
/// while formatting for display.
class MoneyFormat {
  const MoneyFormat({
    this.symbol = r'$',
    this.position = SymbolPosition.start,
    this.decimalPlaces = 2,
    this.grouping = NumberGrouping.western,
  });

  final String symbol;
  final SymbolPosition position;
  final int decimalPlaces;
  final NumberGrouping grouping;

  int get _factor => _pow10(decimalPlaces);

  NumberFormat get _number {
    final decimals = decimalPlaces > 0 ? '.${'0' * decimalPlaces}' : '';
    final pattern = switch (grouping) {
      NumberGrouping.western => '#,##0$decimals',
      NumberGrouping.indian => '#,##,##0$decimals',
    };
    return NumberFormat(pattern, 'en_US');
  }

  /// Number only, no symbol: `1,234.50`.
  String formatAmount(int minor) {
    final negative = minor < 0;
    final abs = minor.abs();
    final whole = abs ~/ _factor;
    final fraction = abs % _factor;
    // Format the whole part with grouping, then append the exact fraction so
    // no floating point rounding is involved.
    final wholeText = _number.format(whole).split('.').first;
    final fractionText = decimalPlaces > 0
        ? '.${fraction.toString().padLeft(decimalPlaces, '0')}'
        : '';
    return '${negative ? '-' : ''}$wholeText$fractionText';
  }

  /// Full money string with symbol: `$1,234.50` or `1,234.50 USh`.
  String format(int minor) {
    final negative = minor < 0;
    final amount = formatAmount(minor.abs());
    final body = position == SymbolPosition.start
        ? '$symbol$amount'
        : '$amount $symbol';
    return negative ? '-$body' : body;
  }

  /// Text for an editable input field (no grouping, no symbol): `1234.50`.
  String toInput(int minor) {
    if (decimalPlaces == 0) return minor.toString();
    final abs = minor.abs();
    final text =
        '${abs ~/ _factor}.${(abs % _factor).toString().padLeft(decimalPlaces, '0')}';
    return minor < 0 ? '-$text' : text;
  }

  /// Parses user input like `12`, `12.5`, `1,200.75` into minor units.
  /// Returns null for invalid input. Extra decimals are rounded half-up.
  int? parse(String input) => parseMinor(input, decimalPlaces);

  static int? parseMinor(String input, int decimalPlaces) {
    var text = input.trim().replaceAll(',', '').replaceAll(' ', '');
    if (text.isEmpty) return null;
    var negative = false;
    if (text.startsWith('-')) {
      negative = true;
      text = text.substring(1);
    }
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(text) || text == '.') return null;
    final parts = text.split('.');
    final whole = parts[0].isEmpty ? 0 : int.parse(parts[0]);
    var fraction = parts.length > 1 ? parts[1] : '';
    var roundUp = false;
    if (fraction.length > decimalPlaces) {
      roundUp = int.parse(fraction[decimalPlaces]) >= 5;
      fraction = fraction.substring(0, decimalPlaces);
    }
    fraction = fraction.padRight(decimalPlaces, '0');
    var minor = whole * _pow10(decimalPlaces) +
        (fraction.isEmpty ? 0 : int.parse(fraction));
    if (roundUp) minor += 1;
    return negative ? -minor : minor;
  }

  static int _pow10(int n) {
    var result = 1;
    for (var i = 0; i < n; i++) {
      result *= 10;
    }
    return result;
  }
}
