import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/sales_repository.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/period.dart';
import '../../../core/utils/pricing.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/display.dart';
import '../../../core/widgets/inputs.dart';
import '../../../core/widgets/pickers.dart';

class _TxnFilter {
  const _TxnFilter({this.query = '', this.period = Period.allTime, this.type, this.status});

  final String query;
  final Period period;
  final String? type;
  final String? status;

  _TxnFilter copyWith({String? query, Period? period, String? Function()? type, String? Function()? status}) =>
      _TxnFilter(
        query: query ?? this.query,
        period: period ?? this.period,
        type: type != null ? type() : this.type,
        status: status != null ? status() : this.status,
      );
}

class _TxnFilterController extends Notifier<_TxnFilter> {
  @override
  _TxnFilter build() => const _TxnFilter();
  void update(_TxnFilter Function(_TxnFilter) f) => state = f(state);
}

final _filterProvider = NotifierProvider<_TxnFilterController, _TxnFilter>(_TxnFilterController.new);

final _txnListProvider = StreamProvider<List<TxnListItem>>((ref) {
  final f = ref.watch(_filterProvider);
  return ref.watch(salesRepositoryProvider).watchTransactions(
        period: f.period,
        query: f.query,
        types: f.type == null ? null : {f.type!},
        statuses: f.status == null ? null : {f.status!},
      );
});

/// Searchable transaction history with period / type / status filters.
class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  Future<void> _openFilters(BuildContext context, WidgetRef ref) async {
    final current = ref.read(_filterProvider);
    final result = await showModalBottomSheet<({String? type, String? status})>(
      context: context,
      useSafeArea: true,
      builder: (_) => _FilterSheet(type: current.type, status: current.status),
    );
    if (result != null) {
      ref.read(_filterProvider.notifier).update((f) => f.copyWith(type: () => result.type, status: () => result.status));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(_filterProvider);
    final list = ref.watch(_txnListProvider);
    final money = ref.watch(moneyFormatProvider);
    final formats = ref.watch(formatsProvider);
    final hasFilters = filter.type != null || filter.status != null;

    return AppScaffold(
      title: l10n.navTransactions,
      trailing: Badge(
        isLabelVisible: hasFilters,
        smallSize: 10,
        child: CircleIconButton(
          icon: Icons.tune,
          tooltip: 'Filter',
          onPressed: () => _openFilters(context, ref),
        ),
      ),
      body: Column(
        children: [
          SearchField(
            hint: l10n.searchTransactions,
            onChanged: (q) => ref.read(_filterProvider.notifier).update((f) => f.copyWith(query: q)),
          ),
          const SizedBox(height: AppSpace.md),
          PeriodSelector(
            label: periodLabel(filter.period, formats),
            onChange: () async {
              final p = await showPeriodPicker(context, filter.period);
              if (p != null) ref.read(_filterProvider.notifier).update((f) => f.copyWith(period: p));
            },
          ),
          const SizedBox(height: AppSpace.sm),
          Expanded(
            child: list.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (items) => items.isEmpty
                  ? const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No transactions',
                      message: 'Sales and payments you record appear here.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: AppSpace.lg),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, i) {
                        final item = items[i];
                        return TransactionTile(
                          typeLabel: '${TxnType.label(item.txn.type)} #${item.txn.number}',
                          title: item.title,
                          subtitle: formats.dateTimeMs(item.txn.date),
                          amount: money.format(item.txn.totalMinor),
                          status: PaymentStatus.fromDb(item.txn.status),
                          onTap: () => context.push('/transactions/${item.txn.id}'),
                        );
                      },
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    label: 'Payment In',
                    icon: Icons.payments_outlined,
                    onPressed: () => context.push('/payment-in'),
                  ),
                ),
                const SizedBox(width: 12),
                CircleIconButton(
                  icon: Icons.add,
                  tooltip: 'New transaction',
                  onPressed: () => showNewTransactionMenu(context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PrimaryButton(
                    label: 'New Sale',
                    icon: Icons.sell_outlined,
                    onPressed: () => context.go('/sell'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({this.type, this.status});
  final String? type;
  final String? status;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _type = widget.type;
  late String? _status = widget.status;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget chips(List<({String? value, String label})> options, String? selected, ValueChanged<String?> onSelect) =>
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in options)
              ChoiceChip(label: Text(o.label), selected: selected == o.value, onSelected: (_) => onSelect(o.value)),
          ],
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.screen, 0, AppSpace.screen, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type', style: text.titleSmall),
            const SizedBox(height: 8),
            chips(
              [(value: null, label: 'All'), (value: TxnType.sale, label: 'Sale'), (value: TxnType.paymentIn, label: 'Payment In')],
              _type,
              (v) => setState(() => _type = v),
            ),
            const SizedBox(height: AppSpace.lg),
            Text('Status', style: text.titleSmall),
            const SizedBox(height: 8),
            chips(
              [
                (value: null, label: 'All'),
                for (final s in PaymentStatus.values) (value: s.dbValue, label: _statusLabel(s)),
              ],
              _status,
              (v) => setState(() => _status = v),
            ),
            const SizedBox(height: AppSpace.xl),
            FormActions(
              primaryLabel: 'Apply',
              secondaryLabel: 'Reset',
              onSecondary: () => Navigator.pop(context, (type: null, status: null)),
              onPrimary: () => Navigator.pop(context, (type: _type, status: _status)),
            ),
          ],
        ),
      ),
    );
  }

  static String _statusLabel(PaymentStatus s) => switch (s) {
        PaymentStatus.paid => 'Paid',
        PaymentStatus.partial => 'Partially paid',
        PaymentStatus.unpaid => 'Unpaid',
        PaymentStatus.voided => 'Void',
      };
}

/// "+" menu grouped into Sales / Purchase / Other. Only P0 types are
/// enabled; the rest are marked "Soon".
Future<void> showNewTransactionMenu(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (sheet) {
      final text = Theme.of(sheet).textTheme;
      Widget grid(List<Widget> tiles) => GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.95,
            children: tiles,
          );
      void go(String route) {
        Navigator.pop(sheet);
        if (route == '/sell') {
          context.go(route);
        } else {
          context.push(route);
        }
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.screen, AppSpace.xl, AppSpace.screen, AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sales Transactions', style: text.titleMedium),
            const SizedBox(height: AppSpace.md),
            grid([
              ActionTile(icon: Icons.sell_outlined, label: 'Sale', onTap: () => go('/sell')),
              ActionTile(icon: Icons.payments_outlined, label: 'Payment In', onTap: () => go('/payment-in')),
              const ActionTile(icon: Icons.assignment_return_outlined, label: 'Sale Return', badge: 'Soon'),
              const ActionTile(icon: Icons.request_quote_outlined, label: 'Quotation', badge: 'Soon'),
            ]),
            const SizedBox(height: AppSpace.lg),
            Text('Purchase Transactions', style: text.titleMedium),
            const SizedBox(height: AppSpace.md),
            grid(const [
              ActionTile(icon: Icons.shopping_cart_outlined, label: 'Purchase', badge: 'Soon'),
              ActionTile(icon: Icons.outbox_outlined, label: 'Payment Out', badge: 'Soon'),
              ActionTile(icon: Icons.undo_outlined, label: 'Debit Note', badge: 'Later'),
            ]),
            const SizedBox(height: AppSpace.lg),
            Text('Other Transactions', style: text.titleMedium),
            const SizedBox(height: AppSpace.md),
            grid(const [
              ActionTile(icon: Icons.account_balance_wallet_outlined, label: 'Expenses', badge: 'Soon'),
              ActionTile(icon: Icons.swap_horiz, label: 'Party to Party Transfer', badge: 'Later'),
            ]),
            const SizedBox(height: AppSpace.lg),
            Center(
              child: CircleIconButton(
                icon: Icons.close,
                tooltip: 'Close',
                onPressed: () => Navigator.pop(sheet),
                color: sheet.colors.textPrimary,
              ),
            ),
          ],
        ),
      );
    },
  );
}
