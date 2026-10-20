/// Pure money / tax math for carts and documents.
///
/// All amounts are integer minor units. Quantities may be fractional
/// (weighed units), so `qty * price` is rounded half away from zero once,
/// at the line level.
library;

/// Rounds a non-integer amount of minor units to the nearest unit.
int roundMinor(double value) => value.round();

/// Gross line amount before any discount.
int lineGross(double qty, int unitPriceMinor) => roundMinor(qty * unitPriceMinor);

/// Discount amount for [percent] (e.g. `10` = 10%) of [grossMinor].
int discountFromPercent(int grossMinor, double percent) =>
    roundMinor(grossMinor * percent / 100);

/// Percentage that [discountMinor] represents of [grossMinor].
double percentFromDiscount(int grossMinor, int discountMinor) =>
    grossMinor == 0 ? 0 : discountMinor * 100 / grossMinor;

/// A tax rate applied to a document. 1500 bps = 15%.
class TaxSpec {
  const TaxSpec({
    required this.id,
    required this.name,
    required this.rateBps,
    required this.inclusive,
  });

  final String id;
  final String name;
  final int rateBps;
  final bool inclusive;
}

/// How much tax each rate contributes, given a taxable base.
class TaxBreakdown {
  const TaxBreakdown({required this.lines, required this.exclusiveMinor, required this.inclusiveMinor});

  final List<({TaxSpec tax, int amountMinor})> lines;

  /// Tax added on top of the base.
  final int exclusiveMinor;

  /// Tax already contained in the base (not added again).
  final int inclusiveMinor;

  int get totalMinor => exclusiveMinor + inclusiveMinor;
}

TaxBreakdown computeTaxes(int baseMinor, List<TaxSpec> taxes) {
  final lines = <({TaxSpec tax, int amountMinor})>[];
  var exclusive = 0;
  var inclusive = 0;

  // Inclusive rates are extracted together from the gross base:
  // net = base / (1 + Σrate), then each rate takes its share of net.
  final inclusiveBps =
      taxes.where((t) => t.inclusive).fold<int>(0, (sum, t) => sum + t.rateBps);
  final net = inclusiveBps == 0
      ? baseMinor
      : roundMinor(baseMinor * 10000 / (10000 + inclusiveBps));

  for (final tax in taxes) {
    if (tax.inclusive) {
      final amount = roundMinor(net * tax.rateBps / 10000);
      inclusive += amount;
      lines.add((tax: tax, amountMinor: amount));
    }
  }
  // Fix rounding drift so inclusive tax + net always equals the base.
  if (inclusiveBps > 0 && inclusive != baseMinor - net && lines.isNotEmpty) {
    final diff = (baseMinor - net) - inclusive;
    final last = lines.removeLast();
    lines.add((tax: last.tax, amountMinor: last.amountMinor + diff));
    inclusive += diff;
  }
  for (final tax in taxes) {
    if (!tax.inclusive) {
      final amount = roundMinor(baseMinor * tax.rateBps / 10000);
      exclusive += amount;
      lines.add((tax: tax, amountMinor: amount));
    }
  }
  return TaxBreakdown(
    lines: lines,
    exclusiveMinor: exclusive,
    inclusiveMinor: inclusive,
  );
}

/// Document totals, all in minor units.
class DocumentTotals {
  const DocumentTotals({
    required this.subtotalMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.exclusiveTaxMinor,
    required this.chargesMinor,
    required this.totalMinor,
  });

  /// Sum of line totals (after line discounts).
  final int subtotalMinor;

  /// Document-level discount.
  final int discountMinor;

  /// All tax, inclusive and exclusive.
  final int taxMinor;
  final int exclusiveTaxMinor;
  final int chargesMinor;
  final int totalMinor;
}

DocumentTotals computeTotals({
  required List<int> lineTotalsMinor,
  int discountMinor = 0,
  List<TaxSpec> taxes = const [],
  int chargesMinor = 0,
}) {
  final subtotal = lineTotalsMinor.fold<int>(0, (a, b) => a + b);
  final discount = discountMinor.clamp(0, subtotal);
  final taxable = subtotal - discount;
  final tax = computeTaxes(taxable, taxes);
  return DocumentTotals(
    subtotalMinor: subtotal,
    discountMinor: discount,
    taxMinor: tax.totalMinor,
    exclusiveTaxMinor: tax.exclusiveMinor,
    chargesMinor: chargesMinor,
    totalMinor: taxable + tax.exclusiveMinor + chargesMinor,
  );
}

enum PaymentStatus {
  paid('paid'),
  partial('partial'),
  unpaid('unpaid'),
  voided('void');

  const PaymentStatus(this.dbValue);

  /// Value stored in `transactions.status`.
  final String dbValue;

  static PaymentStatus fromDb(String value) =>
      values.firstWhere((s) => s.dbValue == value, orElse: () => unpaid);
}

PaymentStatus paymentStatusFor({required int totalMinor, required int paidMinor}) {
  if (paidMinor >= totalMinor) return PaymentStatus.paid;
  if (paidMinor > 0) return PaymentStatus.partial;
  return PaymentStatus.unpaid;
}
