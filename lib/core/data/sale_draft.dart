import '../utils/pricing.dart';

/// Payment modes offered at checkout. `credit` means nothing was paid now.
enum PaymentMode {
  cash('cash', 'Cash'),
  card('card', 'Card'),
  mobileMoney('mobile_money', 'Mobile Money'),
  bank('bank', 'Bank Transfer'),
  credit('credit', 'Credit (unpaid)');

  const PaymentMode(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static PaymentMode fromDb(String value) =>
      values.firstWhere((m) => m.dbValue == value, orElse: () => cash);
}

/// One cart / invoice line.
class SaleLine {
  const SaleLine({
    this.productId,
    required this.name,
    this.unit = 'pcs',
    required this.qty,
    required this.unitPriceMinor,
    this.discountMinor = 0,
    this.costPriceMinor = 0,
    this.taxRateId,
  });

  final String? productId;
  final String name;
  final String unit;
  final double qty;
  final int unitPriceMinor;
  final int discountMinor;
  final int costPriceMinor;
  final String? taxRateId;

  int get grossMinor => lineGross(qty, unitPriceMinor);
  int get totalMinor => grossMinor - discountMinor.clamp(0, grossMinor);

  SaleLine copyWith({double? qty, int? unitPriceMinor, int? discountMinor}) => SaleLine(
        productId: productId,
        name: name,
        unit: unit,
        qty: qty ?? this.qty,
        unitPriceMinor: unitPriceMinor ?? this.unitPriceMinor,
        discountMinor: discountMinor ?? this.discountMinor,
        costPriceMinor: costPriceMinor,
        taxRateId: taxRateId,
      );
}

class ChargeLine {
  const ChargeLine({required this.label, required this.amountMinor});
  final String label;
  final int amountMinor;
}

/// Everything needed to save a sale.
class SaleDraft {
  const SaleDraft({
    required this.date,
    required this.lines,
    this.partyId,
    this.discountMinor = 0,
    this.taxes = const [],
    this.charges = const [],
    this.paymentMode = PaymentMode.cash,
    this.receivedMinor,
    this.notes = '',
  });

  final DateTime date;
  final List<SaleLine> lines;
  final String? partyId;
  final int discountMinor;
  final List<TaxSpec> taxes;
  final List<ChargeLine> charges;
  final PaymentMode paymentMode;

  /// Cash handed over. Null means "exact amount". Ignored for credit.
  final int? receivedMinor;
  final String notes;

  DocumentTotals get totals => computeTotals(
        lineTotalsMinor: [for (final l in lines) l.totalMinor],
        discountMinor: discountMinor,
        taxes: taxes,
        chargesMinor: charges.fold(0, (s, c) => s + c.amountMinor),
      );

  /// Amount actually applied to the invoice (never more than the total).
  int get paidMinor {
    if (paymentMode == PaymentMode.credit) return 0;
    final total = totals.totalMinor;
    final received = receivedMinor ?? total;
    return received.clamp(0, total);
  }

  int get changeMinor {
    if (paymentMode == PaymentMode.credit) return 0;
    final received = receivedMinor ?? totals.totalMinor;
    final change = received - totals.totalMinor;
    return change > 0 ? change : 0;
  }

  PaymentStatus get status =>
      paymentStatusFor(totalMinor: totals.totalMinor, paidMinor: paidMinor);
}
