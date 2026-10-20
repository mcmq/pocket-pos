import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/data/sales_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/pricing.dart';

String _latin1(String s) =>
    String.fromCharCodes(s.replaceAll('–', '-').replaceAll('·', '-').runes.map((r) => r < 256 ? r : 0x3F));

/// A4 sales report: KPIs plus one row per sale.
Future<Uint8List> buildSalesReportPdf({
  required Shop shop,
  required String periodLabel,
  required SalesSummary summary,
  required List<TxnListItem> sales,
  required MoneyFormat money,
  required AppFormats formats,
}) {
  final latin1Symbol = money.symbol.codeUnits.every((u) => u < 256);
  final m = latin1Symbol
      ? money
      : MoneyFormat(
          symbol: shop.currencyCode,
          position: SymbolPosition.end,
          decimalPlaces: money.decimalPlaces,
          grouping: money.grouping,
        );
  final doc = pw.Document(title: 'Sales report', author: shop.name);

  pw.Widget kpi(String label, String value) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(8),
          margin: const pw.EdgeInsets.only(right: 6),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              pw.SizedBox(height: 4),
              pw.Text(_latin1(value), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
      );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Text(_latin1(shop.name), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text(_latin1('Sales report · $periodLabel'), style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 12),
        pw.Row(children: [
          kpi('Total sales', '${summary.count}'),
          kpi('Total amount', m.format(summary.totalMinor)),
          kpi('Received', m.format(summary.receivedMinor)),
          kpi('Unpaid', m.format(summary.unpaidMinor)),
        ]),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: ['Number', 'Date', 'Customer', 'Status', 'Total', 'Paid'],
          headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignments: {4: pw.Alignment.centerRight, 5: pw.Alignment.centerRight},
          data: [
            for (final s in sales)
              [
                s.txn.number,
                _latin1(formats.dateMs(s.txn.date)),
                _latin1(s.title),
                PaymentStatus.fromDb(s.txn.status).dbValue,
                _latin1(m.format(s.txn.totalMinor)),
                _latin1(m.format(s.txn.paidMinor)),
              ],
          ],
        ),
      ],
    ),
  );
  return doc.save();
}
