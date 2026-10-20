import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/catalog_repository.dart';
import '../../../core/data/image_store.dart';
import '../../../core/data/shop_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/display.dart';
import '../../../core/widgets/image_field.dart';
import '../../../core/widgets/inputs.dart';

final _productProvider = StreamProvider.autoDispose.family<Product?, String>(
  (ref, id) => ref.watch(catalogRepositoryProvider).watchProduct(id),
);

final _movementsProvider = StreamProvider.autoDispose.family<List<StockMovement>, String>(
  (ref, id) => ref.watch(catalogRepositoryProvider).watchMovements(id),
);

/// Create or edit a product. [productId] null = new product.
class ProductFormScreen extends ConsumerWidget {
  const ProductFormScreen({super.key, this.productId, this.barcode});

  final String? productId;
  final String? barcode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (productId == null) return _ProductForm(initial: null, barcode: barcode);
    final product = ref.watch(_productProvider(productId!));
    return product.when(
      loading: () => const AppScaffold(showBack: true, body: Center(child: CircularProgressIndicator())),
      error: (e, _) => AppScaffold(showBack: true, body: Center(child: Text('$e'))),
      data: (p) => p == null
          ? const AppScaffold(showBack: true, body: EmptyState(icon: Icons.inventory_2_outlined, title: 'Product not found'))
          : _ProductForm(key: ValueKey(p.id), initial: p),
    );
  }
}

class _ProductForm extends ConsumerStatefulWidget {
  const _ProductForm({super.key, required this.initial, this.barcode});

  final Product? initial;
  final String? barcode;

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  final _form = GlobalKey<FormState>();
  late final Product? p = widget.initial;
  late final _name = TextEditingController(text: p?.name);
  late final _description = TextEditingController(text: p?.description);
  late final _sku = TextEditingController(text: p?.sku);
  late final _barcode = TextEditingController(text: p?.barcode ?? widget.barcode);
  late final _salePrice = TextEditingController(text: p == null ? '' : _money.toInput(p!.salePriceMinor));
  late final _purchasePrice = TextEditingController(text: p == null ? '' : _money.toInput(p!.purchasePriceMinor));
  late final _openingStock = TextEditingController();
  late final _lowStock = TextEditingController(text: p == null ? '' : formatQty(p!.lowStockThreshold));
  late String _unit = p?.unit ?? 'pcs';
  late String? _categoryId = p?.categoryId;
  late String? _taxRateId = p?.taxRateId;
  late bool _trackStock = p?.trackStock ?? true;
  late bool _active = p?.active ?? true;
  late final String _id = p?.id ?? newId();
  File? _pickedImage;
  bool _removeImage = false;
  bool _saving = false;

  MoneyFormat get _money => ref.read(moneyFormatProvider);

  @override
  void dispose() {
    for (final c in [_name, _description, _sku, _barcode, _salePrice, _purchasePrice, _openingStock, _lowStock]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final code = await context.push<String>('/scan');
    if (code != null) setState(() => _barcode.text = code);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final money = ref.read(moneyFormatProvider);
    final images = ref.read(imageStoreProvider);
    String? newImage;
    try {
      final picked = _pickedImage;
      if (picked != null) newImage = await images.save(picked.path, _id);
      final image = newImage != null
          ? ImageEdit.set(newImage)
          : _removeImage
              ? ImageEdit.remove
              : ImageEdit.keep;
      await ref.read(catalogRepositoryProvider).saveProduct(
            ProductDraft(
              id: _id,
              name: _name.text,
              description: _description.text,
              categoryId: _categoryId,
              sku: _sku.text,
              barcode: _barcode.text,
              unit: _unit,
              salePriceMinor: money.parse(_salePrice.text) ?? 0,
              purchasePriceMinor: money.parse(_purchasePrice.text) ?? 0,
              taxRateId: _taxRateId,
              lowStockThreshold: double.tryParse(_lowStock.text) ?? 0,
              trackStock: _trackStock,
              active: _active,
              image: image,
            ),
            openingStock: double.tryParse(_openingStock.text) ?? 0,
          );
      if (!image.unchanged) await images.delete(p?.imageLocalPath);
      if (mounted) context.pop();
    } on DuplicateBarcodeException catch (e) {
      await images.delete(newImage);
      if (mounted) showAppSnack(context, e.toString());
      setState(() => _saving = false);
    } catch (e) {
      await images.delete(newImage);
      if (mounted) showAppSnack(context, 'Could not save: $e');
      setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete ${p!.name}?',
      message: 'It disappears from the product list. Past sales keep their receipts.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(catalogRepositoryProvider).deleteProduct(p!.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(moneyFormatProvider);
    final categories = ref.watch(categoriesProvider).value ?? const <ProductCategory>[];
    final taxRates = ref.watch(taxRatesProvider).value ?? const <TaxRate>[];
    final c = context.colors;
    final fractional = fractionalUnits.contains(_unit);
    final priceFormatter = DecimalInputFormatter(decimals: money.decimalPlaces);
    final qtyFormatter = DecimalInputFormatter(decimals: fractional ? 3 : 0);
    const gap = SizedBox(height: AppSpace.md);

    return AppScaffold(
      title: p == null ? 'New Item' : 'Edit Item',
      showBack: true,
      trailing: p == null
          ? null
          : CircleIconButton(icon: Icons.delete_outline, tooltip: 'Delete item', color: c.danger, onPressed: _delete),
      bottom: FormActions(primaryLabel: 'Save Item', busy: _saving, onPrimary: _save),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpace.lg),
          children: [
            if (p != null) ...[
              _StockCard(product: p!),
              gap,
            ],
            ImageField(
              label: 'Product photo',
              name: _name.text.isEmpty ? '?' : _name.text,
              seed: _id,
              imagePath: _removeImage ? null : p?.imageLocalPath,
              imageUrl: _removeImage ? null : p?.imageUrl,
              pickedFile: _pickedImage,
              onPicked: (f) => setState(() {
                _pickedImage = f;
                _removeImage = false;
              }),
              onRemove: () => setState(() {
                _pickedImage = null;
                _removeImage = true;
              }),
            ),
            gap,
            LabeledField(
              label: 'Name',
              controller: _name,
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
            ),
            gap,
            LabeledField(
              label: 'Description',
              controller: _description,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
            gap,
            Row(
              children: [
                Expanded(
                  child: LabeledField(
                    label: 'Sale price',
                    controller: _salePrice,
                    keyboardType: TextInputType.numberWithOptions(decimal: money.decimalPlaces > 0),
                    inputFormatters: [priceFormatter],
                    prefix: _Symbol(money.symbol),
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: LabeledField(
                    label: 'Purchase price',
                    controller: _purchasePrice,
                    keyboardType: TextInputType.numberWithOptions(decimal: money.decimalPlaces > 0),
                    inputFormatters: [priceFormatter],
                    prefix: _Symbol(money.symbol),
                  ),
                ),
              ],
            ),
            gap,
            Row(
              children: [
                Expanded(
                  child: LabeledDropdown<String?>(
                    label: 'Category',
                    value: _categoryId,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      for (final cat in categories) DropdownMenuItem(value: cat.id, child: Text(cat.name)),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: LabeledDropdown<String>(
                    label: 'Unit',
                    value: _unit,
                    items: [for (final u in {...productUnits, _unit}) DropdownMenuItem(value: u, child: Text(u))],
                    onChanged: (v) => setState(() => _unit = v ?? 'pcs'),
                  ),
                ),
              ],
            ),
            gap,
            Row(
              children: [
                Expanded(child: LabeledField(label: 'SKU', controller: _sku)),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: LabeledField(
                    label: 'Barcode',
                    controller: _barcode,
                    suffix: IconButton(
                      tooltip: 'Scan barcode',
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: _scanBarcode,
                    ),
                  ),
                ),
              ],
            ),
            gap,
            LabeledDropdown<String?>(
              label: 'Default tax',
              value: taxRates.any((t) => t.id == _taxRateId) ? _taxRateId : null,
              items: [
                const DropdownMenuItem(value: null, child: Text('No tax')),
                for (final t in taxRates) DropdownMenuItem(value: t.id, child: Text(t.label)),
              ],
              onChanged: (v) => setState(() => _taxRateId = v),
            ),
            gap,
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Column(
                children: [
                  SettingsTile(
                    icon: Icons.inventory_outlined,
                    label: 'Track stock',
                    switchValue: _trackStock,
                    onSwitch: (v) => setState(() => _trackStock = v),
                  ),
                  const Divider(indent: 12, endIndent: 12),
                  SettingsTile(
                    icon: Icons.visibility_outlined,
                    label: 'Active (shown on sell screen)',
                    switchValue: _active,
                    onSwitch: (v) => setState(() => _active = v),
                  ),
                ],
              ),
            ),
            if (_trackStock) ...[
              gap,
              Row(
                children: [
                  if (p == null) ...[
                    Expanded(
                      child: LabeledField(
                        label: 'Opening stock',
                        controller: _openingStock,
                        hint: '0',
                        keyboardType: TextInputType.numberWithOptions(decimal: fractional),
                        inputFormatters: [qtyFormatter],
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                  ],
                  Expanded(
                    child: LabeledField(
                      label: 'Low-stock alert at',
                      controller: _lowStock,
                      hint: '0',
                      keyboardType: TextInputType.numberWithOptions(decimal: fractional),
                      inputFormatters: [qtyFormatter],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Symbol extends StatelessWidget {
  const _Symbol(this.symbol);
  final String symbol;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 18, right: 4),
        child: Center(
          widthFactor: 1,
          child: Text(symbol, style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
}

/// Current stock, adjust button and the movement history.
class _StockCard extends ConsumerWidget {
  const _StockCard({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final formats = ref.watch(formatsProvider);
    final movements = ref.watch(_movementsProvider(product.id)).value ?? const [];
    if (!product.trackStock) return const SizedBox.shrink();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('In stock', style: text.bodyMedium),
                    Text(
                      '${formatQty(product.stockQty)} ${product.unit}',
                      style: AppText.amount(context, size: 22, color: product.stockQty < 0 ? c.danger : null),
                    ),
                  ],
                ),
              ),
              GhostAddButton(
                label: 'Adjust',
                icon: Icons.tune,
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => _AdjustSheet(product: product),
                ),
              ),
            ],
          ),
          if (movements.isNotEmpty) ...[
            const Divider(height: 24),
            Text('History', style: text.titleSmall),
            const SizedBox(height: 4),
            for (final m in movements.take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.note.isNotEmpty ? m.note : _reasonLabel(m.reason), style: text.bodyMedium),
                          Text(formats.dateTimeMs(m.createdAt), style: text.labelSmall),
                        ],
                      ),
                    ),
                    Text(
                      '${m.qtyDelta > 0 ? '+' : ''}${formatQty(m.qtyDelta)}',
                      style: AppText.amount(context, size: 14, color: m.qtyDelta < 0 ? c.danger : c.success),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  static String _reasonLabel(String reason) => switch (reason) {
        'sale' => 'Sale',
        'sale_return' => 'Sale return',
        'purchase' => 'Purchase',
        'purchase_return' => 'Purchase return',
        'opening' => 'Opening stock',
        'void' => 'Voided sale',
        _ => 'Adjustment',
      };
}

class _AdjustSheet extends ConsumerStatefulWidget {
  const _AdjustSheet({required this.product});
  final Product product;

  @override
  ConsumerState<_AdjustSheet> createState() => _AdjustSheetState();
}

enum _AdjustMode { add, remove, count }

class _AdjustSheetState extends ConsumerState<_AdjustSheet> {
  _AdjustMode _mode = _AdjustMode.add;
  AdjustmentReason _reason = AdjustmentReason.countCorrection;
  final _qty = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = double.tryParse(_qty.text);
    if (value == null) return;
    setState(() => _saving = true);
    final repo = ref.read(catalogRepositoryProvider);
    switch (_mode) {
      case _AdjustMode.count:
        await repo.setCountedStock(productId: widget.product.id, counted: value, note: _note.text);
      case _AdjustMode.add:
        await repo.adjustStock(productId: widget.product.id, delta: value, reason: _reason, note: _note.text);
      case _AdjustMode.remove:
        await repo.adjustStock(productId: widget.product.id, delta: -value, reason: _reason, note: _note.text);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final fractional = fractionalUnits.contains(widget.product.unit);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.screen,
        0,
        AppSpace.screen,
        MediaQuery.viewInsetsOf(context).bottom + AppSpace.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Adjust stock · ${widget.product.name}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpace.md),
          SegmentedButton<_AdjustMode>(
            segments: const [
              ButtonSegment(value: _AdjustMode.add, label: Text('Add'), icon: Icon(Icons.add)),
              ButtonSegment(value: _AdjustMode.remove, label: Text('Remove'), icon: Icon(Icons.remove)),
              ButtonSegment(value: _AdjustMode.count, label: Text('Set count'), icon: Icon(Icons.fact_check_outlined)),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() {
              _mode = s.first;
              if (_mode == _AdjustMode.remove) _reason = AdjustmentReason.damage;
              if (_mode == _AdjustMode.add) _reason = AdjustmentReason.countCorrection;
            }),
          ),
          const SizedBox(height: AppSpace.md),
          LabeledField(
            label: _mode == _AdjustMode.count ? 'Counted quantity' : 'Quantity',
            controller: _qty,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(decimal: fractional),
            inputFormatters: [DecimalInputFormatter(decimals: fractional ? 3 : 0)],
          ),
          if (_mode != _AdjustMode.count) ...[
            const SizedBox(height: AppSpace.md),
            LabeledDropdown<AdjustmentReason>(
              label: 'Reason',
              value: _reason,
              items: [for (final r in AdjustmentReason.values) DropdownMenuItem(value: r, child: Text(r.label))],
              onChanged: (r) => setState(() => _reason = r ?? _reason),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          LabeledField(label: 'Note (optional)', controller: _note),
          const SizedBox(height: AppSpace.xl),
          FormActions(primaryLabel: 'Save', busy: _saving, onPrimary: _save),
        ],
      ),
    );
  }
}
