import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/sale_draft.dart';
import '../../../core/data/sales_repository.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/pricing.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/display.dart';
import 'receipt_screen.dart';

/// Transaction detail with reshare, receive payment and void.
class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({super.key, required this.txnId});

  final String txnId;

  Future<void> _void(BuildContext context, WidgetRef ref, TxnDetail d) async {
    final isSale = d.txn.type == TxnType.sale;
    final ok = await confirmDialog(
      context,
      title: 'Void ${d.txn.number}?',
      message: isSale
          ? 'The sale stays in history marked VOID, its stock is returned and its payments are cancelled.'
          : 'The payment stays in history marked VOID and no longer counts towards any balance.',
      confirmLabel: 'Void',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(salesRepositoryProvider).voidTransaction(d.txn.id);
    if (context.mounted) showAppSnack(context, '${d.txn.number} voided');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(txnDetailProvider(txnId));
    final money = ref.watch(moneyFormatProvider);
    final formats = ref.watch(formatsProvider);
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return detail.when(
      loading: () => const AppScaffold(showBack: true, body: Center(child: CircularProgressIndicator())),
      error: (e, _) => AppScaffold(showBack: true, body: Center(child: Text('$e'))),
      data: (d) {
        if (d == null) {
          return const AppScaffold(
            showBack: true,
            body: EmptyState(icon: Icons.receipt_long_outlined, title: 'Transaction not found'),
          );
        }
        final txn = d.txn;
        final isVoid = d.status == PaymentStatus.voided;
        final canReceive = txn.type == TxnType.sale && !isVoid && d.balanceMinor > 0;

        return AppScaffold(
          title: '${TxnType.label(txn.type)} ${txn.number}',
          showBack: true,
          trailing: isVoid
              ? null
              : PopupMenuButton<String>(
                  tooltip: 'More actions',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (v) {
                    if (v == 'void') _void(context, ref, d);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'void', child: Text('Void', style: TextStyle(color: c.danger))),
                  ],
                ),
          bottom: Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Receipt',
                  icon: Icons.ios_share,
                  onPressed: () => context.push('/receipt/${txn.id}'),
                ),
              ),
              if (canReceive) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: PrimaryButton(
                    label: 'Receive Payment',
                    icon: Icons.payments_outlined,
                    onPressed: () => context.push('/payment-in?saleId=${txn.id}'),
                  ),
                ),
              ],
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: AppSpace.lg),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(d.party?.name ?? (txn.type == TxnType.sale ? 'Cash Sale' : 'No party'), style: text.titleMedium),
                        ),
                        StatusBadge.payment(context, d.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(formats.dateTimeMs(txn.date), style: text.bodyMedium),
                    if (d.party?.phone.isNotEmpty ?? false) Text(d.party!.phone, style: text.bodyMedium),
                    const SizedBox(height: AppSpace.md),
                    AmountRow(label: 'Total', amount: money.format(txn.totalMinor), emphasize: true),
                    AmountRow(label: 'Paid', amount: money.format(txn.paidMinor)),
                    if (d.balanceMinor > 0 && !isVoid)
                      AmountRow(label: 'Balance due', amount: money.format(d.balanceMinor), color: c.danger),
                  ],
                ),
              ),
              if (d.items.isNotEmpty) ...[
                const SectionHeader('Items'),
                AppCard(
                  child: Column(
                    children: [
                      for (var i = 0; i < d.items.length; i++) ...[
                        if (i > 0) const Divider(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(d.items[i].nameSnapshot, style: text.bodyLarge),
                                  Text(
                                    '${formatQty(d.items[i].qty)} ${d.items[i].unitSnapshot} × ${money.format(d.items[i].unitPriceMinor)}'
                                    '${d.items[i].discountMinor > 0 ? ' · −${money.format(d.items[i].discountMinor)}' : ''}',
                                    style: text.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                            Text(money.format(d.items[i].lineTotalMinor), style: AppText.amount(context)),
                          ],
                        ),
                      ],
                      const Divider(height: 24),
                      AmountRow(label: 'Subtotal', amount: money.format(txn.subtotalMinor)),
                      if (txn.discountMinor > 0)
                        AmountRow(label: 'Discount', amount: '−${money.format(txn.discountMinor)}'),
                      for (final t in d.taxes)
                        AmountRow(
                          label: '${t.name} ${formatQty(t.rateBps / 100)}%${t.inclusive ? ' (incl.)' : ''}',
                          amount: money.format(t.amountMinor),
                        ),
                      for (final ch in d.charges) AmountRow(label: ch.label, amount: money.format(ch.amountMinor)),
                    ],
                  ),
                ),
              ],
              if (d.payments.isNotEmpty) ...[
                const SectionHeader('Payments'),
                AppCard(
                  child: Column(
                    children: [
                      for (final p in d.payments)
                        AmountRow(
                          label: '${PaymentMode.fromDb(p.mode).label} · ${formats.dateMs(p.date)}',
                          amount: money.format(p.amountMinor),
                        ),
                    ],
                  ),
                ),
              ],
              if (txn.notes.isNotEmpty) ...[
                const SectionHeader('Notes'),
                AppCard(child: Text(txn.notes, style: text.bodyLarge)),
              ],
              if (txn.syncStatus != 'synced')
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.lg),
                  child: Text(
                    txn.syncStatus == 'error' ? 'Sync error: will retry.' : 'Saved on this device · waiting to sync',
                    style: text.labelSmall,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
