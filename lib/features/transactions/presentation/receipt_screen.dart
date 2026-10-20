import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/data/image_store.dart';
import '../../../core/data/sale_draft.dart';
import '../../../core/data/sales_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/buttons.dart';
import '../data/receipt_pdf.dart';

final txnDetailProvider = StreamProvider.autoDispose.family<TxnDetail?, String>(
  (ref, id) => ref.watch(salesRepositoryProvider).watchDetail(id),
);

/// Receipt view after a sale, and reshare from history. Shares as PDF or
/// PNG through the system share sheet.
class ReceiptScreen extends ConsumerStatefulWidget {
  const ReceiptScreen({super.key, required this.txnId, this.justSold = false});

  final String txnId;
  final bool justSold;

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  final _boundary = GlobalKey();
  bool _busy = false;

  Rect? _shareOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _sharePdf(TxnDetail detail, Shop shop) async {
    setState(() => _busy = true);
    try {
      final bytes = await buildReceiptPdf(
        detail: detail,
        shop: shop,
        logo: await loadReceiptLogo(shop, ref.read(imageStoreProvider)),
        money: ref.read(moneyFormatProvider),
        formats: ref.read(formatsProvider),
      );
      await Printing.sharePdf(bytes: bytes, filename: 'receipt-${detail.txn.number}.pdf', bounds: _shareOrigin());
    } catch (e) {
      if (mounted) showAppSnack(context, 'Could not share PDF: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareImage(TxnDetail detail) async {
    setState(() => _busy = true);
    try {
      final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final bytes = data!.buffer.asUint8List();
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'image/png', name: 'receipt-${detail.txn.number}.png')],
        fileNameOverrides: ['receipt-${detail.txn.number}.png'],
        sharePositionOrigin: _shareOrigin(),
      ));
    } catch (e) {
      if (mounted) showAppSnack(context, 'Could not share image: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(txnDetailProvider(widget.txnId));
    final shop = ref.watch(currentShopProvider).value;
    final c = context.colors;

    return AppScaffold(
      title: 'Receipt',
      showBack: true,
      bottom: detail.value == null || shop == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        label: 'Share PDF',
                        icon: Icons.picture_as_pdf_outlined,
                        onPressed: _busy ? null : () => _sharePdf(detail.value!, shop),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SecondaryButton(
                        label: 'Share Image',
                        icon: Icons.image_outlined,
                        onPressed: _busy ? null : () => _shareImage(detail.value!),
                      ),
                    ),
                  ],
                ),
                if (widget.justSold) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: PrimaryButton(
                      label: 'New Sale',
                      icon: Icons.add_shopping_cart,
                      onPressed: () => context.go('/sell'),
                    ),
                  ),
                ],
              ],
            ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (d) {
          if (d == null || shop == null) {
            return const EmptyState(icon: Icons.receipt_long_outlined, title: 'Receipt not found');
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: AppSpace.lg),
            child: Column(
              children: [
                if (widget.justSold)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.md),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: c.success),
                        const SizedBox(width: 8),
                        Text('Sale saved', style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                  ),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: RepaintBoundary(
                      key: _boundary,
                      child: ReceiptView(
                        detail: d,
                        shop: shop,
                        logo: receiptLogoImage(shop, ref.watch(imageStoreProvider)),
                        money: ref.watch(moneyFormatProvider),
                        formats: ref.watch(formatsProvider),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// On-screen receipt. Also rendered to PNG for image sharing, so it uses
/// a fixed light palette regardless of theme (receipts are white paper).
class ReceiptView extends StatelessWidget {
  const ReceiptView({
    super.key,
    required this.detail,
    required this.shop,
    required this.money,
    required this.formats,
    this.logo,
  });

  final TxnDetail detail;
  final Shop shop;

  /// Shop logo, see [receiptLogoImage].
  final ImageProvider? logo;
  final MoneyFormat money;
  final AppFormats formats;

  @override
  Widget build(BuildContext context) {
    const paper = AppColors.light;
    final txn = detail.txn;
    final small = TextStyle(fontSize: 12, color: paper.textSecondary);
    final body = TextStyle(fontSize: 13, color: paper.textPrimary);
    final bold = body.copyWith(fontWeight: FontWeight.w600);

    Widget row(String label, String value, {TextStyle? style}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(label, style: style ?? body)),
              const SizedBox(width: 8),
              Text(value, style: (style ?? body).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
        );

    final divider = Divider(color: paper.outline, height: 20);

    return Container(
      padding: const EdgeInsets.all(AppSpace.xl),
      decoration: BoxDecoration(
        color: paper.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: paper.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (logo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Center(
                child: Image(
                  image: logo!,
                  height: 64,
                  fit: BoxFit.contain,
                  // A logo that fails to load just leaves the header text.
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          Text(shop.name, textAlign: TextAlign.center, style: bold.copyWith(fontSize: 18)),
          for (final line in [shop.address, shop.phone, if (shop.taxId.isNotEmpty) 'Tax ID: ${shop.taxId}', shop.receiptHeader])
            if (line.trim().isNotEmpty) Text(line, textAlign: TextAlign.center, style: small),
          divider,
          row('${TxnType.label(txn.type)} ${txn.number}', formats.dateTimeMs(txn.date), style: small),
          row('Customer', detail.party?.name ?? 'Cash Sale', style: small),
          if (detail.status.dbValue == 'void')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('VOID', textAlign: TextAlign.center, style: bold.copyWith(color: paper.danger, letterSpacing: 4)),
            ),
          divider,
          for (final item in detail.items) ...[
            Text(item.nameSnapshot, style: bold),
            row(
              '${formatQty(item.qty)} ${item.unitSnapshot} × ${money.format(item.unitPriceMinor)}'
              '${item.discountMinor > 0 ? '  (−${money.format(item.discountMinor)})' : ''}',
              money.format(item.lineTotalMinor),
              style: small,
            ),
            const SizedBox(height: 4),
          ],
          if (detail.items.isNotEmpty) divider,
          if (txn.type == TxnType.sale) ...[
            row('Subtotal', money.format(txn.subtotalMinor)),
            if (txn.discountMinor > 0) row('Discount', '−${money.format(txn.discountMinor)}'),
            for (final t in detail.taxes)
              row('${t.name} ${formatQty(t.rateBps / 100)}%${t.inclusive ? ' (incl.)' : ''}', money.format(t.amountMinor)),
            for (final ch in detail.charges) row(ch.label, money.format(ch.amountMinor)),
          ],
          row('Total', money.format(txn.totalMinor), style: bold.copyWith(fontSize: 16, color: paper.primary)),
          const SizedBox(height: 6),
          row('Paid · ${PaymentMode.fromDb(txn.paymentMode).label}', money.format(txn.paidMinor)),
          if (detail.balanceMinor > 0 && txn.status != 'void')
            row('Balance due', money.format(detail.balanceMinor), style: bold.copyWith(color: paper.danger)),
          if (txn.notes.isNotEmpty) ...[const SizedBox(height: 8), Text(txn.notes, style: small)],
          if (shop.receiptFooter.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(shop.receiptFooter, textAlign: TextAlign.center, style: small),
          ],
        ],
      ),
    );
  }
}

/// The shop logo for [ReceiptView]: this device's file, else the uploaded
/// copy, else none.
ImageProvider? receiptLogoImage(Shop shop, ImageStore images) {
  final file = images.resolve(shop.logoLocalPath);
  if (file != null && file.existsSync()) return FileImage(file);
  final url = shop.logoUrl;
  return url == null || url.isEmpty ? null : CachedNetworkImageProvider(url);
}
