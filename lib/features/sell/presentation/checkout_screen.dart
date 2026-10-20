import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/sale_draft.dart';
import '../../../core/data/sales_repository.dart';
import '../../../core/data/shop_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/pricing.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/display.dart';
import '../../../core/widgets/inputs.dart';
import '../../../core/widgets/pickers.dart';
import 'cart_controller.dart';
import 'cart_sheet.dart';

final _nextNumberProvider = FutureProvider.autoDispose<String>(
  (ref) => ref.watch(salesRepositoryProvider).peekNextNumber(),
);

/// Confirm Sale: invoice number / date, customer, items, discount, tax,
/// charges, payment and notes. Saving is one atomic local transaction.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  DateTime _date = DateTime.now();
  Party? _party;
  int _discount = 0;
  Set<String>? _taxIds;
  final List<ChargeLine> _charges = [];
  PaymentMode _mode = PaymentMode.cash;
  final _received = TextEditingController();
  final _notes = TextEditingController();
  bool _itemsExpanded = false;
  bool _saving = false;

  @override
  void dispose() {
    _received.dispose();
    _notes.dispose();
    super.dispose();
  }

  MoneyFormat get _money => ref.read(moneyFormatProvider);

  SaleDraft _draft(List<SaleLine> lines, List<TaxRate> rates) {
    final taxIds = _taxIds ?? {for (final l in lines) ?l.taxRateId};
    return SaleDraft(
      date: _date,
      lines: lines,
      partyId: _party?.id,
      discountMinor: _discount,
      taxes: [for (final r in rates) if (taxIds.contains(r.id)) r.spec],
      charges: List.of(_charges),
      paymentMode: _mode,
      receivedMinor: _received.text.trim().isEmpty ? null : _money.parse(_received.text),
      notes: _notes.text,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    final now = DateTime.now();
    setState(() => _date = DateTime(picked.year, picked.month, picked.day, now.hour, now.minute));
  }

  Future<void> _pickParty() async {
    final choice = await showPartyPicker(context);
    if (choice == null) return;
    setState(() => _party = switch (choice) {
          WalkIn() => null,
          PickedParty(:final party) => party,
        });
    if (_party == null && _mode == PaymentMode.credit) setState(() => _mode = PaymentMode.cash);
  }

  Future<void> _editDiscount(int subtotal) async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _DiscountDialog(subtotal: subtotal, initial: _discount, money: _money),
    );
    if (result != null) setState(() => _discount = result);
  }

  Future<void> _editTaxes(List<TaxRate> rates, Set<String> current) async {
    if (rates.isEmpty) {
      final go = await confirmDialog(
        context,
        title: 'No tax rates yet',
        message: 'Add tax rates in Settings → Tax rates first.',
        confirmLabel: 'Open settings',
      );
      if (go && mounted) context.push('/settings/taxes');
      return;
    }
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      useSafeArea: true,
      builder: (_) => _TaxSheet(rates: rates, selected: current),
    );
    if (result != null) setState(() => _taxIds = result);
  }

  Future<void> _addCharge() async {
    final result = await showDialog<ChargeLine>(
      context: context,
      builder: (_) => _ChargeDialog(money: _money),
    );
    if (result != null) setState(() => _charges.add(result));
  }

  Future<void> _save(SaleDraft draft) async {
    if (_mode == PaymentMode.credit && _party == null) {
      showAppSnack(context, 'Pick a customer for a credit sale.');
      return;
    }
    setState(() => _saving = true);
    try {
      final txn = await ref.read(salesRepositoryProvider).completeSale(draft);
      ref.read(cartProvider.notifier).clear();
      if (mounted) context.pushReplacement('/receipt/${txn.id}?new=1');
    } catch (e) {
      if (mounted) showAppSnack(context, 'Could not save sale: $e');
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final money = ref.watch(moneyFormatProvider);
    final formats = ref.watch(formatsProvider);
    final lines = ref.watch(cartProvider);
    final rates = ref.watch(taxRatesProvider).value ?? const <TaxRate>[];
    final number = ref.watch(_nextNumberProvider).value ?? '…';

    if (lines.isEmpty && !_saving) {
      return AppScaffold(
        title: 'Confirm Sale',
        showBack: true,
        body: EmptyState(
          icon: Icons.shopping_basket_outlined,
          title: 'Cart is empty',
          action: PrimaryButton(label: 'Back to products', onPressed: () => context.pop()),
        ),
      );
    }

    final draft = _draft(lines, rates);
    final totals = draft.totals;
    final selectedTaxIds = _taxIds ?? {for (final l in lines) ?l.taxRateId};
    final tax = computeTaxes(totals.subtotalMinor - totals.discountMinor, draft.taxes);

    return AppScaffold(
      title: 'Confirm Sale',
      showBack: true,
      bottom: FormActions(
        primaryLabel: 'Save Sale',
        busy: _saving,
        onPrimary: lines.isEmpty ? null : () => _save(draft),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpace.lg),
        children: [
          Row(
            children: [
              Expanded(child: _InfoCard(label: 'Invoice Number', value: number)),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: _InfoCard(
                  label: 'Invoice Date',
                  value: formats.date.format(_date),
                  icon: Icons.calendar_month_outlined,
                  onTap: _pickDate,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          AppCard(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            radius: AppRadius.pill,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: c.surfaceTint, shape: BoxShape.circle),
                  child: Icon(_party == null ? Icons.storefront : Icons.person_outline, color: c.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_party?.name ?? 'Cash Sale', style: text.bodyLarge?.copyWith(fontSize: 16)),
                ),
                GhostAddButton(label: 'Change', icon: Icons.sync, onPressed: _pickParty),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  title: Text('Billing Items (${lines.length})', style: text.bodyLarge),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Add more items',
                        icon: const Icon(Icons.add),
                        onPressed: () => context.pop(),
                      ),
                      Icon(_itemsExpanded ? Icons.expand_less : Icons.expand_more),
                    ],
                  ),
                  onTap: () => setState(() => _itemsExpanded = !_itemsExpanded),
                ),
                if (_itemsExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: [
                        for (var i = 0; i < lines.length; i++) ...[
                          if (i > 0) const Divider(height: 20),
                          CartLineTile(
                            line: lines[i],
                            money: money,
                            onQty: (q) => ref.read(cartProvider.notifier).setQty(i, q),
                            onEdit: () async {
                              final edited = await showItemEditSheet(context, lines[i], money);
                              if (edited != null) ref.read(cartProvider.notifier).replace(i, edited);
                            },
                            onDelete: () => ref.read(cartProvider.notifier).remove(i),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              GhostAddButton(
                label: _discount > 0 ? 'Edit Discount' : 'Add Discount',
                icon: _discount > 0 ? Icons.edit_outlined : Icons.add,
                onPressed: () => _editDiscount(totals.subtotalMinor),
              ),
              GhostAddButton(
                label: selectedTaxIds.isEmpty ? 'Add Tax' : 'Edit Tax',
                icon: selectedTaxIds.isEmpty ? Icons.add : Icons.edit_outlined,
                onPressed: () => _editTaxes(rates, selectedTaxIds),
              ),
              GhostAddButton(label: 'Add Additional Charges', onPressed: _addCharge),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          AppCard(
            child: Column(
              children: [
                AmountRow(label: 'Subtotal', amount: money.format(totals.subtotalMinor)),
                if (totals.discountMinor > 0)
                  AmountRow(label: 'Discount', amount: '−${money.format(totals.discountMinor)}', color: c.success),
                for (final t in tax.lines)
                  AmountRow(
                    label: '${t.tax.name} ${formatQty(t.tax.rateBps / 100)}%${t.tax.inclusive ? ' (incl.)' : ''}',
                    amount: money.format(t.amountMinor),
                  ),
                for (var i = 0; i < _charges.length; i++)
                  InkWell(
                    onLongPress: () => setState(() => _charges.removeAt(i)),
                    child: Row(
                      children: [
                        Expanded(
                          child: AmountRow(label: _charges[i].label, amount: money.format(_charges[i].amountMinor)),
                        ),
                        IconButton(
                          tooltip: 'Remove charge',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.close, size: 18, color: c.textSecondary),
                          onPressed: () => setState(() => _charges.removeAt(i)),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 20),
                AmountRow(label: 'Total Amount', amount: money.format(totals.totalMinor), emphasize: true),
                const SizedBox(height: AppSpace.md),
                LabeledDropdown<PaymentMode>(
                  label: 'Payment Mode',
                  value: _mode,
                  items: [
                    for (final m in PaymentMode.values)
                      DropdownMenuItem(value: m, child: Text(m.label)),
                  ],
                  onChanged: (m) => setState(() => _mode = m ?? PaymentMode.cash),
                ),
                if (_mode != PaymentMode.credit) ...[
                  const SizedBox(height: AppSpace.md),
                  LabeledField(
                    label: 'Amount Received',
                    controller: _received,
                    hint: money.toInput(totals.totalMinor),
                    keyboardType: TextInputType.numberWithOptions(decimal: money.decimalPlaces > 0),
                    inputFormatters: [DecimalInputFormatter(decimals: money.decimalPlaces)],
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                const SizedBox(height: AppSpace.md),
                Row(
                  children: [
                    StatusBadge.payment(context, draft.status),
                    const Spacer(),
                    if (draft.changeMinor > 0)
                      Text('Change due ${money.format(draft.changeMinor)}', style: AppText.amount(context, color: c.success))
                    else if (draft.paidMinor < totals.totalMinor)
                      Text(
                        'Balance ${money.format(totals.totalMinor - draft.paidMinor)}',
                        style: AppText.amount(context, color: c.danger),
                      ),
                  ],
                ),
                if (_mode == PaymentMode.credit && _party == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Credit sales need a customer.', style: text.labelSmall?.copyWith(color: c.danger)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          LabeledField(label: 'Notes or Remarks', controller: _notes, maxLines: 3),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.label, required this.value, this.icon, this.onTap});

  final String label;
  final String value;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodyMedium),
          const Divider(height: 16),
          Row(
            children: [
              Expanded(child: Text(value, style: text.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (icon != null) Icon(icon, size: 20, color: context.colors.textSecondary),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiscountDialog extends StatefulWidget {
  const _DiscountDialog({required this.subtotal, required this.initial, required this.money});

  final int subtotal;
  final int initial;
  final MoneyFormat money;

  @override
  State<_DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<_DiscountDialog> {
  late final _amount = TextEditingController(text: widget.initial == 0 ? '' : widget.money.toInput(widget.initial));
  late final _percent = TextEditingController(
    text: widget.initial == 0 ? '' : formatQty(percentFromDiscount(widget.subtotal, widget.initial)),
  );

  @override
  void dispose() {
    _amount.dispose();
    _percent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final decimals = widget.money.decimalPlaces;
    return AlertDialog(
      title: const Text('Discount'),
      content: Row(
        children: [
          Expanded(
            child: LabeledField(
              label: '%',
              controller: _percent,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [DecimalInputFormatter(decimals: 2)],
              onChanged: (v) {
                final pct = (double.tryParse(v) ?? 0).clamp(0, 100).toDouble();
                _amount.text = pct == 0 ? '' : widget.money.toInput(discountFromPercent(widget.subtotal, pct));
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LabeledField(
              label: 'Amount',
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.numberWithOptions(decimal: decimals > 0),
              inputFormatters: [DecimalInputFormatter(decimals: decimals)],
              onChanged: (v) {
                final amt = widget.money.parse(v) ?? 0;
                _percent.text = amt == 0 ? '' : formatQty(percentFromDiscount(widget.subtotal, amt));
              },
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, 0), child: const Text('Remove')),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            (widget.money.parse(_amount.text) ?? 0).clamp(0, widget.subtotal),
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _TaxSheet extends StatefulWidget {
  const _TaxSheet({required this.rates, required this.selected});

  final List<TaxRate> rates;
  final Set<String> selected;

  @override
  State<_TaxSheet> createState() => _TaxSheetState();
}

class _TaxSheetState extends State<_TaxSheet> {
  late final Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.screen, 0, AppSpace.screen, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Taxes', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpace.sm),
            for (final r in widget.rates)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _selected.contains(r.id),
                title: Text(r.label),
                onChanged: (v) => setState(() => v == true ? _selected.add(r.id) : _selected.remove(r.id)),
              ),
            const SizedBox(height: AppSpace.md),
            FormActions(primaryLabel: 'Apply', onPrimary: () => Navigator.pop(context, _selected)),
          ],
        ),
      ),
    );
  }
}

class _ChargeDialog extends StatefulWidget {
  const _ChargeDialog({required this.money});
  final MoneyFormat money;

  @override
  State<_ChargeDialog> createState() => _ChargeDialogState();
}

class _ChargeDialogState extends State<_ChargeDialog> {
  final _label = TextEditingController(text: 'Delivery');
  final _amount = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Additional charge'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final s in const ['Delivery', 'Packaging', 'Service'])
                ActionChip(label: Text(s), onPressed: () => _label.text = s),
            ],
          ),
          const SizedBox(height: 12),
          LabeledField(label: 'Label', controller: _label, textCapitalization: TextCapitalization.sentences),
          const SizedBox(height: 12),
          LabeledField(
            label: 'Amount',
            controller: _amount,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(decimal: widget.money.decimalPlaces > 0),
            inputFormatters: [DecimalInputFormatter(decimals: widget.money.decimalPlaces)],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final amount = widget.money.parse(_amount.text) ?? 0;
            if (amount <= 0 || _label.text.trim().isEmpty) return;
            Navigator.pop(context, ChargeLine(label: _label.text.trim(), amountMinor: amount));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
