import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/catalog_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/display.dart';
import '../../../core/widgets/inputs.dart';

const _all = '__all';
const _low = '__low';

class _InvFilter extends Notifier<({String query, String chip})> {
  @override
  ({String query, String chip}) build() => (query: '', chip: _all);
  void setQuery(String q) => state = (query: q, chip: state.chip);
  void setChip(String c) => state = (query: state.query, chip: c);
}

final _invFilterProvider = NotifierProvider<_InvFilter, ({String query, String chip})>(_InvFilter.new);

final _inventoryProvider = StreamProvider<List<Product>>((ref) {
  final f = ref.watch(_invFilterProvider);
  return ref.watch(catalogRepositoryProvider).watchProducts(
        query: f.query,
        lowStockOnly: f.chip == _low,
        categoryId: f.chip == _all || f.chip == _low ? null : f.chip,
      );
});

/// Product list with stock, prices and a low-stock filter.
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(_invFilterProvider);
    final categories = ref.watch(categoriesProvider).value ?? const <ProductCategory>[];
    final products = ref.watch(_inventoryProvider);
    final categoryNames = {for (final c in categories) c.id: c.name};

    return AppScaffold(
      title: l10n.navInventory,
      trailing: PillButton(
        label: 'Categories',
        icon: Icons.category_outlined,
        onPressed: () => context.push('/categories'),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: FloatingActionButton.extended(
          heroTag: 'add-product',
          onPressed: () => context.push('/products/new'),
          icon: const Icon(Icons.add),
          label: const Text('Add New Item'),
        ),
      ),
      body: Column(
        children: [
          SearchField(
            hint: l10n.searchProducts,
            onChanged: ref.read(_invFilterProvider.notifier).setQuery,
          ),
          const SizedBox(height: AppSpace.md),
          CategoryChips<String>(
            options: [
              (value: _all, label: 'All'),
              (value: _low, label: 'Low stock'),
              for (final c in categories) (value: c.id, label: c.name),
            ],
            selected: filter.chip,
            onSelected: ref.read(_invFilterProvider.notifier).setChip,
          ),
          const SizedBox(height: AppSpace.md),
          Expanded(
            child: products.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (items) => items.isEmpty
                  ? EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: filter.chip == _low ? 'Nothing is low on stock' : 'No products',
                      message: filter.chip == _low ? null : 'Tap "Add New Item" to create one.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
                      itemBuilder: (context, i) => _InventoryRow(
                        product: items[i],
                        category: categoryNames[items[i].categoryId],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryRow extends ConsumerWidget {
  const _InventoryRow({required this.product, this.category});

  final Product product;
  final String? category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final money = ref.watch(moneyFormatProvider);
    final negative = product.trackStock && product.stockQty < 0;
    final low = product.trackStock && product.stockQty <= product.lowStockThreshold;

    Widget metric(String label, String value, {Color? color}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: text.labelSmall),
            const SizedBox(height: 2),
            Text(value, style: AppText.amount(context, size: 13, color: color)),
          ],
        );

    return AppCard(
      onTap: () => context.push('/products/${product.id}'),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProductThumb(
            name: product.name,
            seed: product.id,
            imagePath: product.imageLocalPath,
            imageUrl: product.imageUrl,
            size: 56,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(product.name, style: text.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (!product.active)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: StatusBadge(label: 'Inactive', fg: c.textSecondary, bg: c.surfaceTint),
                      ),
                    CategoryBadge(category ?? 'Uncategorised'),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: metric('Sales', money.format(product.salePriceMinor))),
                    Expanded(child: metric('Purchase', money.format(product.purchasePriceMinor))),
                    Expanded(
                      child: metric(
                        'Quantity',
                        product.trackStock ? '${formatQty(product.stockQty)} ${product.unit}' : '—',
                        color: negative ? c.danger : (low ? c.warning : null),
                      ),
                    ),
                  ],
                ),
                if (negative)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: StatusBadge(label: 'Negative stock: review', fg: c.danger, bg: c.dangerBg),
                  )
                else if (low)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: StatusBadge(label: 'Low stock', fg: c.warning, bg: c.warningBg),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
