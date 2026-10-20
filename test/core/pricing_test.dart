import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pos/core/data/sale_draft.dart';
import 'package:pocket_pos/core/utils/pricing.dart';

void main() {
  const vat15 = TaxSpec(id: 'v', name: 'VAT', rateBps: 1500, inclusive: false);
  const vat15Incl = TaxSpec(id: 'vi', name: 'VAT', rateBps: 1500, inclusive: true);

  test('line discount percent and amount stay linked', () {
    expect(discountFromPercent(4500, 10), 450);
    expect(percentFromDiscount(4500, 450), 10);
    expect(percentFromDiscount(0, 10), 0);
  });

  test('fractional quantities round once per line', () {
    expect(lineGross(1.333, 300), 400); // 399.9 → 400
    expect(lineGross(2, 750), 1500);
  });

  test('exclusive tax is added on top of the discounted subtotal', () {
    final t = computeTotals(
      lineTotalsMinor: [1000, 1000],
      discountMinor: 200,
      taxes: [vat15],
      chargesMinor: 100,
    );
    expect(t.subtotalMinor, 2000);
    expect(t.taxMinor, 270); // 15% of 1800
    expect(t.totalMinor, 1800 + 270 + 100);
  });

  test('inclusive tax is extracted, not added', () {
    final t = computeTotals(lineTotalsMinor: [1150], taxes: [vat15Incl]);
    expect(t.taxMinor, 150);
    expect(t.totalMinor, 1150);
  });

  test('inclusive tax plus net always equals the base', () {
    const a = TaxSpec(id: 'a', name: 'A', rateBps: 500, inclusive: true);
    const b = TaxSpec(id: 'b', name: 'B', rateBps: 700, inclusive: true);
    for (final base in [1, 99, 1001, 33333]) {
      final tax = computeTaxes(base, [a, b]);
      final net = (base * 10000 / 11200).round();
      expect(tax.inclusiveMinor, base - net);
    }
  });

  test('discount cannot exceed subtotal', () {
    final t = computeTotals(lineTotalsMinor: [500], discountMinor: 900);
    expect(t.discountMinor, 500);
    expect(t.totalMinor, 0);
  });

  group('SaleDraft payment', () {
    SaleDraft draft({PaymentMode mode = PaymentMode.cash, int? received}) => SaleDraft(
          date: DateTime(2026),
          lines: const [SaleLine(name: 'Tea', qty: 2, unitPriceMinor: 250)],
          paymentMode: mode,
          receivedMinor: received,
        );

    test('exact cash is paid', () {
      final d = draft();
      expect(d.paidMinor, 500);
      expect(d.status, PaymentStatus.paid);
      expect(d.changeMinor, 0);
    });

    test('over-payment gives change, capped paid amount', () {
      final d = draft(received: 1000);
      expect(d.paidMinor, 500);
      expect(d.changeMinor, 500);
    });

    test('partial and credit', () {
      expect(draft(received: 200).status, PaymentStatus.partial);
      expect(draft(mode: PaymentMode.credit, received: 500).status, PaymentStatus.unpaid);
    });
  });
}
