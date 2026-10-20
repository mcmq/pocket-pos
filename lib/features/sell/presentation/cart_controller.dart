import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/sale_draft.dart';
import '../../../core/database/app_database.dart';

/// The in-progress cart. Kept in memory; parked carts are P1.
class CartController extends Notifier<List<SaleLine>> {
  @override
  List<SaleLine> build() => const [];

  /// Adds one unit of [product], merging with an existing line.
  void add(Product product) {
    final index = state.indexWhere((l) => l.productId == product.id);
    if (index >= 0) {
      setQty(index, state[index].qty + 1);
      return;
    }
    state = [
      ...state,
      SaleLine(
        productId: product.id,
        name: product.name,
        unit: product.unit,
        qty: 1,
        unitPriceMinor: product.salePriceMinor,
        costPriceMinor: product.purchasePriceMinor,
        taxRateId: product.taxRateId,
      ),
    ];
  }

  void setQty(int index, double qty) {
    if (qty <= 0) {
      remove(index);
      return;
    }
    final line = state[index];
    // Keep a line discount from exceeding the new gross.
    final next = line.copyWith(qty: qty);
    state = [
      for (var i = 0; i < state.length; i++)
        i == index ? next.copyWith(discountMinor: next.discountMinor.clamp(0, next.grossMinor)) : state[i],
    ];
  }

  void replace(int index, SaleLine line) {
    state = [for (var i = 0; i < state.length; i++) i == index ? line : state[i]];
  }

  void remove(int index) {
    state = [...state]..removeAt(index);
  }

  void clear() => state = const [];
}

final cartProvider = NotifierProvider<CartController, List<SaleLine>>(CartController.new);

final cartTotalProvider = Provider<int>(
  (ref) => ref.watch(cartProvider).fold(0, (sum, l) => sum + l.totalMinor),
);
