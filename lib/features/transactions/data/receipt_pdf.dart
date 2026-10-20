import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' show networkImage;

import '../../../core/data/image_store.dart';
import '../../../core/data/sale_draft.dart';
import '../../../core/data/sales_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/qty.dart';

/// The built-in PDF font only covers Latin-1, so symbols such as ₹ or ₦
/// fall back to the currency code. Bundling a Unicode font is a follow-up.
MoneyFormat pdfSafeMoney(MoneyFormat money, String currencyCode) {
  final latin1 = money.symbol.codeUnits.every((u) => u < 256);
  if (latin1) return money;
  return MoneyFormat(
    symbol: currencyCode,
    position: SymbolPosition.end,
    decimalPlaces: money.decimalPlaces,
    grouping: money.grouping,
  );
}

String _latin1(String s) => String.fromCharCodes(
      s.replaceAll('−', '-').replaceAll('×', 'x').replaceAll('–', '-').replaceAll('·', '-').runes.map((r) => r < 256 ? r : 0x3F),
    );

/// The shop logo for the PDF: this device's file, else the uploaded copy.
/// Null when there is none or it can't be loaded (e.g. offline).
Future<pw.ImageProvider?> loadReceiptLogo(Shop shop, ImageStore images) async {
  try {
    final file = images.resolve(shop.logoLocalPath);
    if (file != null && await file.exists()) return pw.MemoryImage(await file.readAsBytes());
    final url = shop.logoUrl;
    if (url != null && url.isNotEmpty) return await networkImage(url);
  } catch (_) {
    // A receipt without its logo beats no receipt.
  }
  return null;
}

/// 80 mm roll receipt.
Future<Uint8List> buildReceiptPdf({
  required TxnDetail detail,
  required Shop shop,
  required MoneyFormat money,
  required AppFormats formats,
  pw.ImageProvider? logo,
}) async {
  final m = pdfSafeMoney(money, shop.currencyCode);
  final txn = detail.txn;
  final doc = pw.Document(title: 'Receipt ${txn.number}', author: shop.name);
  const small = pw.TextStyle(fontSize: 8);
  const body = pw.TextStyle(fontSize: 9);
  final bold = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);

  pw.Widget row(String label, String value, {pw.TextStyle? style}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(
          children: [
            pw.Expanded(child: pw.Text(_latin1(label), style: style ?? body)),
            pw.Text(_latin1(value), style: style ?? body),
          ],
        ),
      );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.roll80.copyWith(
        marginLeft: 6 * PdfPageFormat.mm,
        marginRight: 6 * PdfPageFormat.mm,
      ),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (logo != null)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Center(child: pw.Image(logo, height: 40, fit: pw.BoxFit.contain)),
            ),
          pw.Text(_latin1(shop.name), textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          for (final line in [shop.address, shop.phone, if (shop.taxId.isNotEmpty) 'Tax ID: ${shop.taxId}', shop.receiptHeader])
            if (line.trim().isNotEmpty) pw.Text(_latin1(line), textAlign: pw.TextAlign.center, style: small),
          pw.SizedBox(height: 6),
          pw.Divider(thickness: 0.5),
          row('${TxnType.label(txn.type)} ${txn.number}', formats.dateTimeMs(txn.date), style: small),
          row('Customer', detail.party?.name ?? 'Cash Sale', style: small),
          if (detail.status.dbValue == 'void') pw.Text('*** VOID ***', textAlign: pw.TextAlign.center, style: bold),
          pw.Divider(thickness: 0.5),
          for (final item in detail.items) ...[
            pw.Text(_latin1(item.nameSnapshot), style: bold),
            row(
              '${formatQty(item.qty)} ${item.unitSnapshot} x ${m.format(item.unitPriceMinor)}'
              '${item.discountMinor > 0 ? '  (-${m.format(item.discountMinor)})' : ''}',
              m.format(item.lineTotalMinor),
            ),
          ],
          pw.Divider(thickness: 0.5),
          if (txn.type == TxnType.sale) ...[
            row('Subtotal', m.format(txn.subtotalMinor)),
            if (txn.discountMinor > 0) row('Discount', '-${m.format(txn.discountMinor)}'),
            for (final t in detail.taxes)
              row('${t.name} ${formatQty(t.rateBps / 100)}%${t.inclusive ? ' incl.' : ''}', m.format(t.amountMinor)),
            for (final c in detail.charges) row(c.label, m.format(c.amountMinor)),
          ],
          row('TOTAL', m.format(txn.totalMinor), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          row('Paid (${PaymentMode.fromDb(txn.paymentMode).label})', m.format(txn.paidMinor)),
          if (detail.balanceMinor > 0) row('Balance due', m.format(detail.balanceMinor), style: bold),
          if (txn.notes.isNotEmpty) ...[pw.SizedBox(height: 6), pw.Text(_latin1(txn.notes), style: small)],
          pw.SizedBox(height: 10),
          if (shop.receiptFooter.isNotEmpty)
            pw.Text(_latin1(shop.receiptFooter), textAlign: pw.TextAlign.center, style: small),
        ],
      ),
    ),
  );
  return doc.save();
}
