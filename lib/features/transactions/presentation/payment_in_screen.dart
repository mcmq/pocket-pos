import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/sale_draft.dart';
import '../../../core/database/app_database.dart';
import '../../../core/data/sales_repository.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/display.dart';
import '../../../core/widgets/inputs.dart';
import '../../../core/widgets/pickers.dart';
import 'receipt_screen.dart';

/// Money received from a customer, optionally against an unpaid sale.
class PaymentInScreen extends ConsumerStatefulWidget {
  const PaymentInScreen({super.key, this.saleId});

  final String? saleId;

  @override
  ConsumerState<PaymentInScreen> createState() => _PaymentInScreenState();
}

class _PaymentInScreenState extends ConsumerState<PaymentInScreen> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  Party? _party;
  PaymentMode _mode = PaymentMode.cash;
  DateTime _date = DateTime.now();
  bool _saving = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save(TxnDetail? sale) async {
    final money = ref.read(moneyFormatProvider);
    final amount = money.parse(_amount.text) ?? 0;
    if (amount <= 0) {
      showAppSnack(context, 'Enter an amount.');
      return;
    }
    if (sale != null && amount > sale.balanceMinor) {
      showAppSnack(context, 'Amount is more than the balance due (${money.format(sale.balanceMinor)}).');
      return;
    }
    setState(() => _saving = true);
    try {
      final txn = await ref.read(salesRepositoryProvider).receivePayment(
            saleId: widget.saleId,
            partyId: _party?.id,
            amountMinor: amount,
            mode: _mode,
            date: _date,
            notes: _notes.text,
          );
      if (mounted) context.pushReplacement('/receipt/${txn.id}');
    } catch (e) {
      if (mounted) showAppSnack(context, 'Could not save payment: $e');
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final money = ref.watch(moneyFormatProvider);
    final formats = ref.watch(formatsProvider);
    final sale = widget.saleId == null ? null : ref.watch(txnDetailProvider(widget.saleId!)).value;

    if (sale != null && !_prefilled) {
      _prefilled = true;
      _party = sale.party;
      _amount.text = money.toInput(sale.balanceMinor);
    }

    return AppScaffold(
      title: 'Payment In',
      showBack: true,
      bottom: FormActions(primaryLabel: 'Save Payment', busy: _saving, onPrimary: () => _save(sale)),
      body: ListView(
        children: [
          if (sale != null)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('For ${TxnType.label(sale.txn.type)} ${sale.txn.number}', style: text.bodyLarge),
                  const SizedBox(height: 8),
                  AmountRow(label: 'Invoice total', amount: money.format(sale.txn.totalMinor)),
                  AmountRow(label: 'Already paid', amount: money.format(sale.txn.paidMinor)),
                  AmountRow(label: 'Balance due', amount: money.format(sale.balanceMinor), color: c.danger),
                ],
              ),
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
                  child: Icon(Icons.person_outline, color: c.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(_party?.name ?? 'No customer', style: text.bodyLarge)),
                if (sale == null)
                  GhostAddButton(
                    label: _party == null ? 'Choose' : 'Change',
                    icon: Icons.sync,
                    onPressed: () async {
                      final choice = await showPartyPicker(context, allowWalkIn: false);
                      if (choice is PickedParty) setState(() => _party = choice.party);
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          LabeledField(
            label: 'Amount',
            controller: _amount,
            autofocus: sale == null,
            keyboardType: TextInputType.numberWithOptions(decimal: money.decimalPlaces > 0),
            inputFormatters: [DecimalInputFormatter(decimals: money.decimalPlaces)],
          ),
          const SizedBox(height: AppSpace.md),
          LabeledDropdown<PaymentMode>(
            label: 'Payment Mode',
            value: _mode,
            items: [
              for (final m in PaymentMode.values)
                if (m != PaymentMode.credit) DropdownMenuItem(value: m, child: Text(m.label)),
            ],
            onChanged: (m) => setState(() => _mode = m ?? PaymentMode.cash),
          ),
          const SizedBox(height: AppSpace.md),
          AppCard(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2015),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              );
              if (picked != null) setState(() => _date = picked);
            },
            radius: AppRadius.pill,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Expanded(child: Text('Date', style: text.bodyMedium)),
                Text(formats.date.format(_date), style: text.bodyLarge),
                const SizedBox(width: 8),
                Icon(Icons.calendar_month_outlined, size: 20, color: c.textSecondary),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          LabeledField(label: 'Notes', controller: _notes, maxLines: 2),
        ],
      ),
    );
  }
}
