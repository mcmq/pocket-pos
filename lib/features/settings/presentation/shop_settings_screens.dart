import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/image_store.dart';
import '../../../core/data/shop_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/display.dart';
import '../../../core/widgets/image_field.dart';
import '../../../core/widgets/inputs.dart';

/// Shop name, contact details and receipt header / footer.
class ShopDetailsScreen extends ConsumerStatefulWidget {
  const ShopDetailsScreen({super.key});

  @override
  ConsumerState<ShopDetailsScreen> createState() => _ShopDetailsScreenState();
}

class _ShopDetailsScreenState extends ConsumerState<ShopDetailsScreen> {
  final _form = GlobalKey<FormState>();
  late final Shop _shop = ref.read(currentShopProvider).value!;
  late final _name = TextEditingController(text: _shop.name);
  late final _phone = TextEditingController(text: _shop.phone);
  late final _address = TextEditingController(text: _shop.address);
  late final _taxId = TextEditingController(text: _shop.taxId);
  late final _header = TextEditingController(text: _shop.receiptHeader);
  late final _footer = TextEditingController(text: _shop.receiptFooter);
  File? _pickedLogo;
  bool _removeLogo = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _taxId, _header, _footer]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final images = ref.read(imageStoreProvider);
    String? newLogo;
    try {
      final picked = _pickedLogo;
      if (picked != null) newLogo = await images.save(picked.path, _shop.id);
      final logo = newLogo != null
          ? ImageEdit.set(newLogo)
          : _removeLogo
              ? ImageEdit.remove
              : ImageEdit.keep;
      await ref.read(shopRepositoryProvider).updateShop(
            (s) => s.copyWith(
              name: _name.text.trim(),
              phone: _phone.text.trim(),
              address: _address.text.trim(),
              taxId: _taxId.text.trim(),
              receiptHeader: _header.text.trim(),
              receiptFooter: _footer.text.trim(),
            ),
            logo: logo,
          );
      if (!logo.unchanged) await images.delete(_shop.logoLocalPath);
      if (mounted) context.pop();
    } catch (e) {
      await images.delete(newLogo);
      if (mounted) showAppSnack(context, 'Could not save: $e');
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpace.md);
    return AppScaffold(
      title: 'Shop & receipt',
      showBack: true,
      bottom: FormActions(primaryLabel: 'Save', busy: _saving, onPrimary: _save),
      body: Form(
        key: _form,
        child: ListView(
          children: [
            ImageField(
              label: 'Logo (shown on receipts)',
              name: _shop.name,
              seed: _shop.id,
              imagePath: _removeLogo ? null : _shop.logoLocalPath,
              imageUrl: _removeLogo ? null : _shop.logoUrl,
              pickedFile: _pickedLogo,
              onPicked: (f) => setState(() {
                _pickedLogo = f;
                _removeLogo = false;
              }),
              onRemove: () => setState(() {
                _pickedLogo = null;
                _removeLogo = true;
              }),
            ),
            gap,
            LabeledField(
              label: 'Shop name',
              controller: _name,
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
            ),
            gap,
            LabeledField(label: 'Phone', controller: _phone, keyboardType: TextInputType.phone),
            gap,
            LabeledField(label: 'Address', controller: _address, maxLines: 2),
            gap,
            LabeledField(label: 'Tax ID', controller: _taxId),
            gap,
            LabeledField(label: 'Receipt header', controller: _header, maxLines: 2, hint: 'e.g. Open daily 7am–9pm'),
            gap,
            LabeledField(label: 'Receipt footer', controller: _footer, maxLines: 2),
          ],
        ),
      ),
    );
  }
}

/// Currency code, symbol, position and decimals.
class CurrencySettingsScreen extends ConsumerStatefulWidget {
  const CurrencySettingsScreen({super.key});

  @override
  ConsumerState<CurrencySettingsScreen> createState() => _CurrencySettingsScreenState();
}

class _CurrencySettingsScreenState extends ConsumerState<CurrencySettingsScreen> {
  late final Shop _shop = ref.read(currentShopProvider).value!;
  late final _code = TextEditingController(text: _shop.currencyCode);
  late final _symbol = TextEditingController(text: _shop.currencySymbol);
  late String _position = _shop.currencyPosition;
  late int _decimals = _shop.decimalPlaces;
  bool _saving = false;

  @override
  void dispose() {
    _code.dispose();
    _symbol.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_decimals != _shop.decimalPlaces) {
      final ok = await confirmDialog(
        context,
        title: 'Change decimal places?',
        message: 'Existing prices are stored in minor units and will be shown with the new decimals. '
            'Only change this before you enter prices.',
        confirmLabel: 'Change',
        destructive: true,
      );
      if (!ok) return;
    }
    setState(() => _saving = true);
    await ref.read(shopRepositoryProvider).updateShop(
          (s) => s.copyWith(
            currencyCode: _code.text.trim().toUpperCase(),
            currencySymbol: _symbol.text.trim(),
            currencyPosition: _position,
            decimalPlaces: _decimals,
          ),
        );
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final grouping = ref.watch(moneyFormatProvider).grouping;
    final preview = MoneyFormat(
      symbol: _symbol.text,
      position: _position == 'end' ? SymbolPosition.end : SymbolPosition.start,
      decimalPlaces: _decimals,
      grouping: grouping,
    );
    const gap = SizedBox(height: AppSpace.md);
    return AppScaffold(
      title: 'Currency',
      showBack: true,
      bottom: FormActions(primaryLabel: 'Save', busy: _saving, onPrimary: _save),
      body: ListView(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in commonCurrencies)
                ChoiceChip(
                  label: Text(c.code),
                  selected: _code.text == c.code,
                  onSelected: (_) => setState(() {
                    _code.text = c.code;
                    _symbol.text = c.symbol;
                    _decimals = c.decimals;
                  }),
                ),
            ],
          ),
          gap,
          Row(
            children: [
              Expanded(child: LabeledField(label: 'Code', controller: _code, onChanged: (_) => setState(() {}))),
              const SizedBox(width: AppSpace.md),
              Expanded(child: LabeledField(label: 'Symbol', controller: _symbol, onChanged: (_) => setState(() {}))),
            ],
          ),
          gap,
          Row(
            children: [
              Expanded(
                child: LabeledDropdown<String>(
                  label: 'Currency Position',
                  value: _position,
                  items: const [
                    DropdownMenuItem(value: 'start', child: Text('Start')),
                    DropdownMenuItem(value: 'end', child: Text('End')),
                  ],
                  onChanged: (v) => setState(() => _position = v ?? 'start'),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: LabeledDropdown<int>(
                  label: 'Decimal places',
                  value: _decimals,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('0')),
                    DropdownMenuItem(value: 2, child: Text('2')),
                    DropdownMenuItem(value: 3, child: Text('3')),
                  ],
                  onChanged: (v) => setState(() => _decimals = v ?? 2),
                ),
              ),
            ],
          ),
          gap,
          AppCard(child: AmountRow(label: 'Preview', amount: preview.format(123456789), emphasize: true)),
        ],
      ),
    );
  }
}

/// Tax rates used at checkout and as product defaults.
class TaxRatesScreen extends ConsumerWidget {
  const TaxRatesScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [TaxRate? rate]) async {
    final result = await showDialog<({String name, int bps, bool inclusive})>(
      context: context,
      builder: (_) => _TaxRateDialog(rate: rate),
    );
    if (result == null) return;
    await ref
        .read(shopRepositoryProvider)
        .saveTaxRate(id: rate?.id, name: result.name, rateBps: result.bps, inclusive: result.inclusive);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final rates = ref.watch(taxRatesProvider).value ?? const <TaxRate>[];
    return AppScaffold(
      title: 'Tax rates',
      showBack: true,
      trailing: PillButton(label: 'Add', icon: Icons.add, filled: true, onPressed: () => _edit(context, ref)),
      body: rates.isEmpty
          ? EmptyState(
              icon: Icons.percent,
              title: 'No tax rates',
              message: 'Add rates like "VAT 15%". Choose inclusive if your prices already contain the tax.',
              action: PrimaryButton(label: 'Add tax rate', onPressed: () => _edit(context, ref)),
            )
          : ListView(
              children: [
                SettingsGroup(children: [
                  for (final r in rates)
                    Row(
                      children: [
                        Expanded(
                          child: SettingsTile(icon: Icons.percent, label: r.label, onTap: () => _edit(context, ref, r)),
                        ),
                        IconButton(
                          tooltip: 'Delete ${r.name}',
                          icon: Icon(Icons.delete_outline, color: c.danger),
                          onPressed: () async {
                            final ok = await confirmDialog(
                              context,
                              title: 'Delete ${r.name}?',
                              message: 'Past sales keep the tax they were charged.',
                              confirmLabel: 'Delete',
                              destructive: true,
                            );
                            if (ok) await ref.read(shopRepositoryProvider).deleteTaxRate(r.id);
                          },
                        ),
                      ],
                    ),
                ]),
              ],
            ),
    );
  }
}

class _TaxRateDialog extends StatefulWidget {
  const _TaxRateDialog({this.rate});
  final TaxRate? rate;

  @override
  State<_TaxRateDialog> createState() => _TaxRateDialogState();
}

class _TaxRateDialogState extends State<_TaxRateDialog> {
  late final _name = TextEditingController(text: widget.rate?.name ?? 'VAT');
  late final _rate = TextEditingController(
    text: widget.rate == null ? '' : (widget.rate!.rateBps / 100).toString().replaceFirst(RegExp(r'\.0$'), ''),
  );
  late bool _inclusive = widget.rate?.inclusive ?? false;

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.rate == null ? 'New tax rate' : 'Edit tax rate'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LabeledField(label: 'Name', controller: _name),
          const SizedBox(height: 12),
          LabeledField(
            label: 'Rate %',
            controller: _rate,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [DecimalInputFormatter(decimals: 2)],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Included in prices'),
            value: _inclusive,
            onChanged: (v) => setState(() => _inclusive = v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final pct = double.tryParse(_rate.text);
            if (pct == null || pct <= 0 || pct > 100 || _name.text.trim().isEmpty) return;
            Navigator.pop(context, (name: _name.text.trim(), bps: (pct * 100).round(), inclusive: _inclusive));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
