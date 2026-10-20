import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/catalog_repository.dart';
import '../../../core/data/sale_draft.dart';
import '../../../core/l10n/app_localizations.dart';
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
import 'cart_controller.dart';

Future<void> showCartSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => _CartContents(scrollController: controller, inSheet: true),
    ),
  );
}

/// Cart side panel for tablets.
class CartPanel extends StatelessWidget {
  const CartPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(padding: EdgeInsets.zero, child: const _CartContents(inSheet: false));
  }
}

class _CartContents extends ConsumerWidget {
  const _CartContents({this.scrollController, required this.inSheet});

  final ScrollController? scrollController;
  final bool inSheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final lines = ref.watch(cartProvider);
    final total = ref.watch(cartTotalProvider);
    final money = ref.watch(moneyFormatProvider);
    final cart = ref.read(cartProvider.notifier);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(AppSpace.screen, inSheet ? 0 : AppSpace.md, 8, 0),
          child: Row(
            children: [
              if (inSheet)
                IconButton(
                  tooltip: 'Close cart',
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: () => Navigator.pop(context),
                ),
              Expanded(child: Text(l10n.cartItemCount(lines.length), style: Theme.of(context).textTheme.titleLarge)),
              if (lines.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Clear cart?',
                      message: 'Remove all items from the cart.',
                      confirmLabel: 'Clear',
                      destructive: true,
                    );
                    if (ok) cart.clear();
                  },
                  style: TextButton.styleFrom(foregroundColor: c.danger),
                  child: const Text('Clear Items', style: TextStyle(fontSize: 15)),
                ),
            ],
          ),
        ),
        Expanded(
          child: lines.isEmpty
              ? const EmptyState(
                  icon: Icons.shopping_basket_outlined,
                  title: 'Cart is empty',
                  message: 'Tap a product to add it.',
                )
              : ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.screen, vertical: AppSpace.sm),
                  itemCount: lines.length,
                  separatorBuilder: (_, _) => const Divider(height: 20),
                  itemBuilder: (context, i) => CartLineTile(
                    line: lines[i],
                    money: money,
                    onQty: (q) => cart.setQty(i, q),
                    onEdit: () async {
                      final edited = await showItemEditSheet(context, lines[i], money);
                      if (edited != null) cart.replace(i, edited);
                    },
                    onDelete: () => cart.remove(i),
                  ),
                ),
        ),
        if (lines.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(AppSpace.screen, AppSpace.md, AppSpace.screen, AppSpace.md),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.outline))),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  AmountRow(label: 'Subtotal', amount: money.format(total), emphasize: true),
                  const SizedBox(height: AppSpace.sm),
                  SizedBox(
                    width: double.infinity,
                    child: PrimaryButton(
                      label: 'Continue Billing',
                      onPressed: () {
                        if (inSheet) Navigator.pop(context);
                        context.push('/checkout');
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A cart line: thumbnail, name, "2 box × $7.50", qty stepper, line total,
/// edit and delete actions.
class CartLineTile extends StatelessWidget {
  const CartLineTile({
    super.key,
    required this.line,
    required this.money,
    required this.onQty,
    required this.onEdit,
    required this.onDelete,
  });

  final SaleLine line;
  final MoneyFormat money;
  final ValueChanged<double> onQty;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProductThumb(name: line.name, seed: line.productId ?? line.name, size: 52),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(line.name, style: text.bodyLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                '${formatQty(line.qty)} ${line.unit} × ${money.format(line.unitPriceMinor)}',
                style: text.bodyMedium,
              ),
              if (line.discountMinor > 0)
                Text('Discount −${money.format(line.discountMinor)}', style: text.labelSmall?.copyWith(color: c.success)),
              const SizedBox(height: 6),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Edit item',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.edit_outlined, size: 20, color: c.textSecondary),
                    onPressed: onEdit,
                  ),
                  IconButton(
                    tooltip: 'Remove item',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.delete_outline, size: 20, color: c.danger),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            QtyStepper(qty: line.qty, onChanged: onQty),
            const SizedBox(height: 10),
            Text(money.format(line.totalMinor), style: AppText.amount(context, color: c.primary)),
          ],
        ),
      ],
    );
  }
}

/// `− n +` stepper.
class QtyStepper extends StatelessWidget {
  const QtyStepper({super.key, required this.qty, required this.onChanged});

  final double qty;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: c.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(icon: Icons.remove, tooltip: 'Decrease', filled: false, onTap: () => onChanged(qty - 1)),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 28),
            child: Text(formatQty(qty), textAlign: TextAlign.center, style: AppText.amount(context, size: 14)),
          ),
          _StepButton(icon: Icons.add, tooltip: 'Increase', filled: true, onTap: () => onChanged(qty + 1)),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.tooltip, required this.filled, required this.onTap});

  final IconData icon;
  final String tooltip;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: filled ? c.primary : c.surfaceTint, shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: filled ? c.onPrimary : c.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// Quantity, rate and a linked discount % / amount pair.
Future<SaleLine?> showItemEditSheet(BuildContext context, SaleLine line, MoneyFormat money) {
  return showModalBottomSheet<SaleLine>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ItemEditSheet(line: line, money: money),
  );
}

class _ItemEditSheet extends StatefulWidget {
  const _ItemEditSheet({required this.line, required this.money});

  final SaleLine line;
  final MoneyFormat money;

  @override
  State<_ItemEditSheet> createState() => _ItemEditSheetState();
}

class _ItemEditSheetState extends State<_ItemEditSheet> {
  late final _qty = TextEditingController(text: formatQty(widget.line.qty));
  late final _rate = TextEditingController(text: widget.money.toInput(widget.line.unitPriceMinor));
  late final _percent = TextEditingController(
    text: widget.line.discountMinor == 0
        ? ''
        : _trimPercent(percentFromDiscount(widget.line.grossMinor, widget.line.discountMinor)),
  );
  late final _amount = TextEditingController(
    text: widget.line.discountMinor == 0 ? '' : widget.money.toInput(widget.line.discountMinor),
  );

  bool get _fractional => fractionalUnits.contains(widget.line.unit);

  static String _trimPercent(double v) =>
      v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

  double get _qtyValue => double.tryParse(_qty.text) ?? 0;
  int get _rateValue => widget.money.parse(_rate.text) ?? 0;
  int get _gross => lineGross(_qtyValue, _rateValue);
  int get _discount => (widget.money.parse(_amount.text) ?? 0).clamp(0, _gross);

  void _fromPercent(String v) {
    final pct = double.tryParse(v) ?? 0;
    _amount.text = pct == 0 ? '' : widget.money.toInput(discountFromPercent(_gross, pct.clamp(0, 100)));
    setState(() {});
  }

  void _fromAmount(String v) {
    final amount = widget.money.parse(v) ?? 0;
    _percent.text = amount == 0 ? '' : _trimPercent(percentFromDiscount(_gross, amount));
    setState(() {});
  }

  /// Quantity or rate changed: keep the percentage, recompute the amount.
  void _baseChanged(String _) {
    if (_percent.text.isNotEmpty) {
      _fromPercent(_percent.text);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    for (final c in [_qty, _rate, _percent, _amount]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final decimals = widget.money.decimalPlaces;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.screen,
        0,
        AppSpace.screen,
        MediaQuery.viewInsetsOf(context).bottom + AppSpace.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.line.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpace.lg),
            Row(
              children: [
                Expanded(
                  child: LabeledField(
                    label: 'Quantity',
                    controller: _qty,
                    keyboardType: TextInputType.numberWithOptions(decimal: _fractional),
                    inputFormatters: [DecimalInputFormatter(decimals: _fractional ? 3 : 0)],
                    onChanged: _baseChanged,
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: LabeledField(
                    label: 'Rate',
                    controller: _rate,
                    keyboardType: TextInputType.numberWithOptions(decimal: decimals > 0),
                    inputFormatters: [DecimalInputFormatter(decimals: decimals)],
                    onChanged: _baseChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: LabeledField(
                    label: 'Discount %',
                    controller: _percent,
                    hint: '0',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [DecimalInputFormatter(decimals: 2)],
                    onChanged: _fromPercent,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                  child: Tooltip(
                    message: 'Percent and amount are linked',
                    child: Icon(Icons.link, color: c.primary),
                  ),
                ),
                Expanded(
                  child: LabeledField(
                    label: 'Discount amount',
                    controller: _amount,
                    hint: '0',
                    keyboardType: TextInputType.numberWithOptions(decimal: decimals > 0),
                    inputFormatters: [DecimalInputFormatter(decimals: decimals)],
                    onChanged: _fromAmount,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              radius: AppRadius.pill,
              child: AmountRow(
                label: 'Total Amount',
                amount: widget.money.format(_gross - _discount),
                emphasize: true,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            FormActions(
              primaryLabel: 'Save Item',
              onPrimary: _qtyValue <= 0
                  ? null
                  : () => Navigator.pop(
                        context,
                        widget.line.copyWith(qty: _qtyValue, unitPriceMinor: _rateValue, discountMinor: _discount),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
