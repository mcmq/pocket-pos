import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../providers/app_providers.dart';
import 'image_store.dart';

export 'image_store.dart' show ImageEdit;

/// Reasons for a manual stock adjustment.
enum AdjustmentReason {
  opening('opening', 'Opening stock'),
  countCorrection('adjustment', 'Count correction'),
  damage('adjustment', 'Damage / loss');

  const AdjustmentReason(this.dbReason, this.label);
  final String dbReason;
  final String label;
}

/// Products, categories and manual stock changes. Local SQLite only; every
/// write also queues its outbox entries in the same transaction.
class CatalogRepository {
  CatalogRepository(this._db, this._session);

  final AppDatabase _db;
  final Session _session;

  String get _shopId => _session.shopId;

  // ---------------------------------------------------------------- reads

  Stream<List<ProductCategory>> watchCategories() {
    return (_db.select(_db.categories)
          ..where((c) => c.shopId.equals(_shopId) & c.deletedAt.isNull())
          ..orderBy([(c) => OrderingTerm.asc(c.sortOrder), (c) => OrderingTerm.asc(c.name)]))
        .watch();
  }

  /// Products matching [query] (name, SKU or barcode) and [categoryId].
  Stream<List<Product>> watchProducts({
    String query = '',
    String? categoryId,
    bool activeOnly = false,
    bool lowStockOnly = false,
    bool favoritesOnly = false,
  }) {
    final q = _db.select(_db.products)
      ..where((p) {
        Expression<bool> e = p.shopId.equals(_shopId) & p.deletedAt.isNull();
        if (activeOnly) e = e & p.active.equals(true);
        if (categoryId != null) e = e & p.categoryId.equals(categoryId);
        if (favoritesOnly) e = e & p.isFavorite.equals(true);
        if (lowStockOnly) {
          e = e & p.trackStock.equals(true) & p.stockQty.isSmallerOrEqual(p.lowStockThreshold);
        }
        final text = query.trim();
        if (text.isNotEmpty) {
          final like = '%${text.replaceAll(RegExp('[%_]'), '')}%';
          e = e &
              (p.name.like(like) |
                  p.sku.like(like) |
                  p.barcode.equals(text) |
                  p.barcode.like(like));
        }
        return e;
      })
      ..orderBy([(p) => OrderingTerm.asc(p.name)]);
    return q.watch();
  }

  Stream<Product?> watchProduct(String id) =>
      (_db.select(_db.products)..where((p) => p.id.equals(id))).watchSingleOrNull();

  Future<Product?> productById(String id) =>
      (_db.select(_db.products)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<Product?> findByBarcode(String code) {
    return (_db.select(_db.products)
          ..where((p) =>
              p.shopId.equals(_shopId) & p.deletedAt.isNull() & p.barcode.equals(code.trim()))
          ..limit(1))
        .getSingleOrNull();
  }

  Stream<List<StockMovement>> watchMovements(String productId) {
    return (_db.select(_db.stockMovements)
          ..where((m) => m.productId.equals(productId) & m.deletedAt.isNull())
          ..orderBy([(m) => OrderingTerm.desc(m.createdAt)]))
        .watch();
  }

  // ----------------------------------------------------------- categories

  Future<ProductCategory> saveCategory({String? id, required String name, int? sortOrder}) {
    return _db.transaction(() async {
      final now = nowMs();
      final existing = id == null
          ? null
          : await (_db.select(_db.categories)..where((c) => c.id.equals(id))).getSingleOrNull();
      final ProductCategory row;
      if (existing == null) {
        final maxSort = await _maxCategorySort();
        row = ProductCategory(
          id: id ?? newId(),
          shopId: _shopId,
          createdAt: now,
          updatedAt: now,
          version: 1,
          syncStatus: 'pending',
          deviceId: _session.deviceId,
          name: name.trim(),
          sortOrder: sortOrder ?? maxSort + 1,
        );
      } else {
        row = existing.copyWith(
          name: name.trim(),
          sortOrder: sortOrder ?? existing.sortOrder,
          updatedAt: now,
          version: existing.version + 1,
          syncStatus: 'pending',
          deviceId: _session.deviceId,
        );
      }
      await _db.into(_db.categories).insertOnConflictUpdate(row);
      await _db.enqueue('categories', row.id, row.toJson());
      return row;
    });
  }

  Future<int> _maxCategorySort() async {
    final max = _db.categories.sortOrder.max();
    final row = await (_db.selectOnly(_db.categories)
          ..addColumns([max])
          ..where(_db.categories.shopId.equals(_shopId)))
        .getSingle();
    return row.read(max) ?? 0;
  }

  /// Soft-deletes the category. Its products become uncategorised.
  Future<void> deleteCategory(String id) {
    return _db.transaction(() async {
      final now = nowMs();
      final cat = await (_db.select(_db.categories)..where((c) => c.id.equals(id))).getSingle();
      final deleted = cat.copyWith(
        deletedAt: Value(now),
        updatedAt: now,
        version: cat.version + 1,
        syncStatus: 'pending',
        deviceId: _session.deviceId,
      );
      await _db.update(_db.categories).replace(deleted);
      await _db.enqueue('categories', id, deleted.toJson());

      final products = await (_db.select(_db.products)
            ..where((p) => p.categoryId.equals(id) & p.deletedAt.isNull()))
          .get();
      for (final p in products) {
        await _writeProduct(p.copyWith(categoryId: const Value(null)), now);
      }
    });
  }

  // ------------------------------------------------------------- products

  /// Creates or updates a product. For a new product, [openingStock] writes
  /// an `opening` stock movement.
  Future<Product> saveProduct(ProductDraft draft, {double openingStock = 0}) {
    return _db.transaction(() async {
      final barcode = draft.barcode?.trim();
      if (barcode != null && barcode.isNotEmpty) {
        final clash = await findByBarcode(barcode);
        if (clash != null && clash.id != draft.id) {
          throw DuplicateBarcodeException(clash.name);
        }
      }
      final now = nowMs();
      final existing = draft.id == null ? null : await productById(draft.id!);
      final base = existing ??
          Product(
            id: draft.id ?? newId(),
            shopId: _shopId,
            createdAt: now,
            updatedAt: now,
            version: 0,
            syncStatus: 'pending',
            deviceId: _session.deviceId,
            name: '',
            description: '',
            unit: 'pcs',
            salePriceMinor: 0,
            purchasePriceMinor: 0,
            stockQty: 0,
            lowStockThreshold: 0,
            trackStock: true,
            active: true,
            isFavorite: false,
          );
      final image = draft.image;
      final row = await _writeProduct(
        base.copyWith(
          // A new picture drops the old URL; the upload queue fills it in.
          imageLocalPath: image.unchanged ? const Value.absent() : Value(image.localPath),
          imageUrl: image.unchanged ? const Value.absent() : const Value(null),
          name: draft.name.trim(),
          description: draft.description.trim(),
          categoryId: Value(draft.categoryId),
          sku: Value(_blankToNull(draft.sku)),
          barcode: Value(_blankToNull(barcode)),
          unit: draft.unit,
          salePriceMinor: draft.salePriceMinor,
          purchasePriceMinor: draft.purchasePriceMinor,
          taxRateId: Value(draft.taxRateId),
          lowStockThreshold: draft.lowStockThreshold,
          trackStock: draft.trackStock,
          active: draft.active,
        ),
        now,
      );
      if (existing == null && openingStock != 0) {
        await _addMovement(row.id, openingStock, 'opening', now: now);
        await _db.recomputeStock(row.id);
      }
      return (await productById(row.id))!;
    });
  }

  Future<void> toggleFavorite(Product p) {
    return _db.transaction(() async {
      await _writeProduct(p.copyWith(isFavorite: !p.isFavorite), nowMs());
    });
  }

  Future<void> deleteProduct(String id) {
    return _db.transaction(() async {
      final p = await productById(id);
      if (p == null) return;
      final now = nowMs();
      await _writeProduct(p.copyWith(deletedAt: Value(now)), now);
    });
  }

  /// Manual stock change. [delta] may be negative.
  Future<void> adjustStock({
    required String productId,
    required double delta,
    required AdjustmentReason reason,
    String note = '',
  }) {
    if (delta == 0) return Future.value();
    return _db.transaction(() async {
      final note0 = note.trim().isEmpty ? reason.label : '${reason.label}: ${note.trim()}';
      await _addMovement(productId, delta, reason.dbReason, note: note0);
      await _db.recomputeStock(productId);
    });
  }

  /// Sets stock to an exact counted value by writing the difference.
  Future<void> setCountedStock({required String productId, required double counted, String note = ''}) async {
    final p = await productById(productId);
    if (p == null) return;
    await adjustStock(
      productId: productId,
      delta: counted - p.stockQty,
      reason: AdjustmentReason.countCorrection,
      note: note,
    );
  }

  Future<Product> _writeProduct(Product p, int now) async {
    final row = p.copyWith(
      updatedAt: now,
      version: p.version + 1,
      syncStatus: 'pending',
      deviceId: _session.deviceId,
    );
    // stock_qty is left out so a stale in-memory row can't overwrite the
    // cached value; only recomputeStock() writes it. Nulls are written, so
    // clearing a category or image sticks.
    await _db.into(_db.products).insertOnConflictUpdate(
          row.toCompanion(false).copyWith(stockQty: const Value.absent()),
        );
    // Stock never syncs as an absolute value; movements carry it.
    await _db.enqueue('products', row.id, row.toJson()..remove('stockQty'));
    return row;
  }

  Future<void> _addMovement(
    String productId,
    double delta,
    String reason, {
    String? transactionId,
    String note = '',
    int? now,
  }) async {
    final ts = now ?? nowMs();
    final m = StockMovement(
      id: newId(),
      shopId: _shopId,
      createdAt: ts,
      updatedAt: ts,
      version: 1,
      syncStatus: 'pending',
      deviceId: _session.deviceId,
      productId: productId,
      qtyDelta: delta,
      reason: reason,
      transactionId: transactionId,
      note: note,
    );
    await _db.into(_db.stockMovements).insert(m);
    await _db.enqueue('stock_movements', m.id, m.toJson());
  }

  static String? _blankToNull(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
}

/// Editable fields of a product.
class ProductDraft {
  const ProductDraft({
    this.id,
    required this.name,
    this.description = '',
    this.categoryId,
    this.sku,
    this.barcode,
    this.unit = 'pcs',
    this.salePriceMinor = 0,
    this.purchasePriceMinor = 0,
    this.taxRateId,
    this.lowStockThreshold = 0,
    this.trackStock = true,
    this.active = true,
    this.image = ImageEdit.keep,
  });

  final String? id;
  final String name;
  final String description;
  final String? categoryId;
  final String? sku;
  final String? barcode;
  final String unit;
  final int salePriceMinor;
  final int purchasePriceMinor;
  final String? taxRateId;
  final double lowStockThreshold;
  final bool trackStock;
  final bool active;
  final ImageEdit image;
}

class DuplicateBarcodeException implements Exception {
  DuplicateBarcodeException(this.productName);
  final String productName;

  @override
  String toString() => 'Barcode already used by "$productName".';
}

/// Units offered in the product form. Units in [fractionalUnits] accept
/// decimal quantities.
const productUnits = ['pcs', 'box', 'pack', 'dozen', 'kg', 'g', 'l', 'ml', 'm'];
const fractionalUnits = {'kg', 'g', 'l', 'ml', 'm'};

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(ref.watch(databaseProvider), ref.watch(sessionProvider)),
);

final categoriesProvider = StreamProvider<List<ProductCategory>>(
  (ref) => ref.watch(catalogRepositoryProvider).watchCategories(),
);
