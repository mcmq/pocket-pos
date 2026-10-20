import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/catalog_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/display.dart';
import '../../../core/widgets/inputs.dart';
import '../../../core/widgets/sync_status_chip.dart';
import 'cart_controller.dart';
import 'cart_sheet.dart';
import 'product_card.dart';

/// Special chip values besides category ids.
const _all = '__all';
const _favorites = '__fav';

final _sellQueryProvider = NotifierProvider<_SellFilter, ({String query, String chip})>(_SellFilter.new);

class _SellFilter extends Notifier<({String query, String chip})> {
  @override
  ({String query, String chip}) build() => (query: '', chip: _all);
  void setQuery(String q) => state = (query: q, chip: state.chip);
  void setChip(String c) => state = (query: state.query, chip: c);
}

final _sellProductsProvider = StreamProvider<List<Product>>((ref) {
  final f = ref.watch(_sellQueryProvider);
  return ref.watch(catalogRepositoryProvider).watchProducts(
        query: f.query,
        activeOnly: true,
        categoryId: f.chip == _all || f.chip == _favorites ? null : f.chip,
        favoritesOnly: f.chip == _favorites,
      );
});

/// Home: product grid with search, category chips and the cart bar.
/// Tablets get the cart side by side.
class SellScreen extends ConsumerWidget {
  const SellScreen({super.key});

  static Future<void> scanToCart(BuildContext context, WidgetRef ref) async {
    final code = await context.push<String>('/scan');
    if (code == null || !context.mounted) return;
    final product = await ref.read(catalogRepositoryProvider).findByBarcode(code);
    if (!context.mounted) return;
    if (product != null) {
      ref.read(cartProvider.notifier).add(product);
      showAppSnack(context, 'Added ${product.name}');
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('No product with barcode $code'),
          action: SnackBarAction(
            label: 'Create product',
            onPressed: () => context.push(Uri(path: '/products/new', queryParameters: {'barcode': code}).toString()),
          ),
        ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final grid = _ProductArea(wide: wide);
    if (!wide) {
      return AppScaffold(
        padBody: false,
        body: Column(
          children: [
            const _SellHeader(),
            Expanded(child: grid),
            const _CartBar(),
          ],
        ),
      );
    }
    return AppScaffold(
      padBody: false,
      body: Column(
        children: [
          const _SellHeader(),
          Expanded(
            child: Row(
              children: [
                Expanded(flex: 3, child: grid),
                const SizedBox(
                  width: 380,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(0, 0, AppSpace.screen, AppSpace.md),
                    child: CartPanel(),
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

class _SellHeader extends ConsumerWidget {
  const _SellHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(currentShopProvider).value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.screen, AppSpace.sm, AppSpace.screen, AppSpace.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              shop?.name ?? 'PocketPOS',
              style: Theme.of(context).textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SyncStatusChip(),
          const SizedBox(width: 8),
          PillButton(label: 'Add Item', icon: Icons.add, onPressed: () => context.push('/products/new')),
        ],
      ),
    );
  }
}

class _ProductArea extends ConsumerWidget {
  const _ProductArea({required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(_sellQueryProvider);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final products = ref.watch(_sellProductsProvider);
    final width = MediaQuery.sizeOf(context).width - (wide ? 380 : 0);
    final columns = (width / 190).floor().clamp(2, 6);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.screen),
          child: SearchField(
            hint: l10n.searchProducts,
            onChanged: ref.read(_sellQueryProvider.notifier).setQuery,
            trailingIcon: Icons.qr_code_scanner,
            trailingTooltip: 'Scan barcode',
            onTrailing: () => SellScreen.scanToCart(context, ref),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.screen),
          child: CategoryChips<String>(
            options: [
              (value: _all, label: 'All'),
              (value: _favorites, label: 'Favorites'),
              for (final c in categories) (value: c.id, label: c.name),
            ],
            selected: filter.chip,
            onSelected: ref.read(_sellQueryProvider.notifier).setChip,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Expanded(
          child: products.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (items) {
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: filter.query.isEmpty && filter.chip == _all ? 'No products yet' : 'No matches',
                  message: filter.query.isEmpty && filter.chip == _all
                      ? 'Add your first product to start selling.'
                      : 'Try another search or category.',
                  action: filter.query.isEmpty && filter.chip == _all
                      ? PrimaryButton(
                          label: 'Add product',
                          icon: Icons.add,
                          onPressed: () => context.push('/products/new'),
                        )
                      : null,
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(AppSpace.screen, 0, AppSpace.screen, AppSpace.lg),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: AppSpace.md,
                  crossAxisSpacing: AppSpace.md,
                  childAspectRatio: 1.08,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) => ProductCard(
                  product: items[i],
                  onTap: () => ref.read(cartProvider.notifier).add(items[i]),
                  onFavorite: () => ref.read(catalogRepositoryProvider).toggleFavorite(items[i]),
                  onLongPress: () => context.push('/products/${items[i].id}'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// "2 Items $05.75  Next" bar. The chevron opens the cart sheet. The count
/// bumps briefly when an item is added.
class _CartBar extends ConsumerStatefulWidget {
  const _CartBar();

  @override
  ConsumerState<_CartBar> createState() => _CartBarState();
}

class _CartBarState extends ConsumerState<_CartBar> with SingleTickerProviderStateMixin {
  late final _bump = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));

  @override
  void dispose() {
    _bump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(cartProvider, (prev, next) {
      final reduceMotion = MediaQuery.of(context).disableAnimations;
      if (!reduceMotion && next.length >= (prev?.length ?? 0) && next.isNotEmpty) {
        _bump.forward(from: 0).then((_) => _bump.reverse());
      }
    });
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final lines = ref.watch(cartProvider);
    final total = ref.watch(cartTotalProvider);
    final money = ref.watch(moneyFormatProvider);
    if (lines.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpace.screen, 0, AppSpace.screen, AppSpace.sm),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: c.outline),
        boxShadow: appFloatingShadow,
      ),
      child: Row(
        children: [
          CircleIconButton(
            icon: Icons.keyboard_arrow_up,
            tooltip: 'Show cart',
            onPressed: () => showCartSheet(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => showCartSheet(context),
              child: ScaleTransition(
                scale: Tween(begin: 1.0, end: 1.08).animate(_bump),
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.cartItemCount(lines.length), style: Theme.of(context).textTheme.labelSmall),
                    Text(money.format(total), style: AppText.amount(context, size: 16, color: c.primary)),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 110,
            child: PrimaryButton(label: l10n.actionNext, onPressed: () => context.push('/checkout')),
          ),
        ],
      ),
    );
  }
}
