import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../core/data/sales_repository.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/period.dart';
import '../../../core/utils/pricing.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/display.dart';
import '../../../core/widgets/pickers.dart';
import '../data/sales_report_pdf.dart';

class _PeriodController extends Notifier<Period> {
  @override
  Period build() => Period.of(PeriodKind.thisMonth);
  void set(Period p) => state = p;
}

final _periodProvider = NotifierProvider<_PeriodController, Period>(_PeriodController.new);

final _summaryProvider = StreamProvider.autoDispose.family<SalesSummary, Period?>((ref, period) {
  if (period == null) return Stream.value(SalesSummary.zero);
  return ref.watch(salesRepositoryProvider).watchSummary(period);
});

final _salesProvider = StreamProvider.autoDispose<List<TxnListItem>>((ref) {
  return ref.watch(salesRepositoryProvider).watchTransactions(
        period: ref.watch(_periodProvider),
        types: {TxnType.sale},
      );
});

final _stockValueProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(salesRepositoryProvider).watchStockValue(),
);

/// Basic sales report: KPIs vs the previous period, stock value and the
/// sales list. Export as PDF. Excel / download exports are P1.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final period = ref.watch(_periodProvider);
    final formats = ref.watch(formatsProvider);
    final money = ref.watch(moneyFormatProvider);
    final current = ref.watch(_summaryProvider(period)).value ?? SalesSummary.zero;
    final previous = ref.watch(_summaryProvider(period.previous)).value;
    final sales = ref.watch(_salesProvider).value ?? const <TxnListItem>[];
    final stockValue = ref.watch(_stockValueProvider).value ?? 0;
    final hasPrevious = period.previous != null;

    String caption(int now, int? before) {
      if (!hasPrevious || before == null) return 'All recorded sales';
      if (before == 0) return now == 0 ? 'No change vs last period' : 'New vs last period';
      final pct = ((now - before) * 100 / before).round();
      return '${pct >= 0 ? '+' : ''}$pct% vs last period';
    }

    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 4 : 2;

    return AppScaffold(
      title: l10n.navReports,
      trailing: CircleIconButton(
        icon: Icons.picture_as_pdf_outlined,
        tooltip: 'Share PDF report',
        onPressed: sales.isEmpty
            ? null
            : () async {
                final shop = ref.read(currentShopProvider).value;
                if (shop == null) return;
                final bytes = await buildSalesReportPdf(
                  shop: shop,
                  periodLabel: periodLabel(period, formats),
                  summary: current,
                  sales: sales,
                  money: money,
                  formats: formats,
                );
                await Printing.sharePdf(bytes: bytes, filename: 'sales-report.pdf');
              },
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: PeriodSelector(
              label: periodLabel(period, formats),
              onChange: () async {
                final p = await showPeriodPicker(context, period);
                if (p != null) ref.read(_periodProvider.notifier).set(p);
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpace.md)),
          SliverGrid.count(
            crossAxisCount: columns,
            mainAxisSpacing: AppSpace.md,
            crossAxisSpacing: AppSpace.md,
            childAspectRatio: 1.25,
            children: [
              StatCard(
                icon: Icons.receipt_long_outlined,
                label: 'Total Sales',
                value: '${current.count} ${current.count == 1 ? 'Entry' : 'Entries'}',
                caption: caption(current.count, previous?.count),
              ),
              StatCard(
                icon: Icons.attach_money,
                label: 'Total Amount',
                value: money.format(current.totalMinor),
                caption: caption(current.totalMinor, previous?.totalMinor),
              ),
              StatCard(
                icon: Icons.call_received,
                label: 'Received Amount',
                value: money.format(current.receivedMinor),
                caption: caption(current.receivedMinor, previous?.receivedMinor),
              ),
              StatCard(
                icon: Icons.pending_actions_outlined,
                label: 'Unpaid Amount',
                value: money.format(current.unpaidMinor),
                caption: caption(current.unpaidMinor, previous?.unpaidMinor),
              ),
            ],
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpace.md)),
          SliverToBoxAdapter(
            child: StatCard(
              icon: Icons.inventory_2_outlined,
              label: 'Stock value (at purchase price)',
              value: money.format(stockValue),
              caption: 'Current inventory valuation',
            ),
          ),
          const SliverToBoxAdapter(child: SectionHeader('Transaction Lists')),
          if (sales.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: AppSpace.xl),
                child: EmptyState(icon: Icons.bar_chart, title: 'No sales in this period'),
              ),
            )
          else
            SliverList.separated(
              itemCount: sales.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, i) => TransactionTile(
                typeLabel: '#${sales[i].txn.number}',
                title: sales[i].title,
                subtitle: formats.dateTimeMs(sales[i].txn.date),
                amount: money.format(sales[i].txn.totalMinor),
                status: PaymentStatus.fromDb(sales[i].txn.status),
                onTap: () => context.push('/transactions/${sales[i].txn.id}'),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
        ],
      ),
    );
  }
}
