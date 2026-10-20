import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pos/core/utils/money.dart';

void main() {
  group('MoneyFormat', () {
    const usd = MoneyFormat();

    test('formats minor units with symbol and grouping', () {
      expect(usd.format(0), r'$0.00');
      expect(usd.format(575), r'$5.75');
      expect(usd.format(123456789), r'$1,234,567.89');
      expect(usd.format(-1050), r'-$10.50');
    });

    test('supports symbol at end, zero decimals and indian grouping', () {
      const ugx = MoneyFormat(symbol: 'USh', position: SymbolPosition.end, decimalPlaces: 0);
      expect(ugx.format(1500000), '1,500,000 USh');
      const inr = MoneyFormat(symbol: '₹', grouping: NumberGrouping.indian);
      expect(inr.format(100000000), '₹10,00,000.00');
    });

    test('parses input without floating point error', () {
      expect(usd.parse('12'), 1200);
      expect(usd.parse('12.5'), 1250);
      expect(usd.parse('1,200.75'), 120075);
      expect(usd.parse('0.29'), 29);
      expect(usd.parse('0.125'), 13);
      expect(usd.parse('abc'), isNull);
      expect(usd.parse(''), isNull);
      expect(const MoneyFormat(decimalPlaces: 0).parse('15.6'), 16);
    });

    test('round-trips through input text', () {
      for (final v in [0, 1, 99, 100, 123456]) {
        expect(usd.parse(usd.toInput(v)), v);
      }
    });
  });
}
