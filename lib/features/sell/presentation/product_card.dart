import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/display.dart';

/// Tinted card: name, 2-line description, price, favorite heart and a
/// thumbnail bottom-right. Tap adds to cart; long-press edits.
class ProductCard extends ConsumerWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    required this.onFavorite,
    this.onLongPress,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final money = ref.watch(moneyFormatProvider);
    final outOfStock = product.trackStock && product.stockQty <= 0;
    final lowStock = product.trackStock && !outOfStock && product.stockQty <= product.lowStockThreshold;

    return Semantics(
      button: true,
      label: '${product.name}, ${money.format(product.salePriceMinor)}. Tap to add to cart.',
      child: Material(
        color: c.tintFor(product.id),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: c.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 36),
                      child: Text(
                        product.name,
                        style: text.bodyLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        product.description.isEmpty ? product.unit : product.description,
                        style: text.labelSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Spacer(),
                    Text(money.format(product.salePriceMinor), style: AppText.amount(context, size: 16)),
                    const SizedBox(height: 4),
                    if (outOfStock)
                      StatusBadge(label: 'Out of stock', fg: c.danger, bg: c.dangerBg)
                    else if (lowStock)
                      StatusBadge(label: 'Low stock', fg: c.warning, bg: c.warningBg)
                    else
                      const SizedBox(height: 19),
                  ],
                ),
                Positioned(
                  top: -6,
                  right: 0,
                  child: IconButton(
                    tooltip: product.isFavorite ? 'Remove from favorites' : 'Add to favorites',
                    onPressed: onFavorite,
                    icon: Icon(
                      product.isFavorite ? Icons.favorite : Icons.favorite_border,
                      size: 20,
                      color: product.isFavorite ? c.danger : c.textSecondary,
                    ),
                  ),
                ),
                Positioned(
                  right: 6,
                  bottom: 0,
                  child: ProductThumb(
                    name: product.name,
                    seed: product.id,
                    imagePath: product.imageLocalPath,
                    imageUrl: product.imageUrl,
                    size: 44,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
