import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../providers/app_providers.dart';
import '../utils/pricing.dart';
import 'image_store.dart';

/// The shop profile (receipt header, currency) and its tax rates.
class ShopRepository {
  ShopRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  String get _deviceId => _ref.read(settingsProvider)[SettingKeys.deviceId]!;

  /// First-launch shop creation. Also seeds a "General" category.
  Future<Shop> createShop({
    required String name,
    required String currencyCode,
    required String currencySymbol,
    String currencyPosition = 'start',
    int decimalPlaces = 2,
    String phone = '',
    String address = '',
    String? ownerUid,
  }) async {
    final shop = await _db.transaction(() async {
      final now = nowMs();
      final id = newId();
      final shop = Shop(
        id: id,
        shopId: id,
        createdAt: now,
        updatedAt: now,
        version: 1,
        syncStatus: 'pending',
        deviceId: _deviceId,
        name: name.trim(),
        phone: phone.trim(),
        address: address.trim(),
        taxId: '',
        currencyCode: currencyCode.trim().toUpperCase(),
        currencySymbol: currencySymbol.trim(),
        currencyPosition: currencyPosition,
        decimalPlaces: decimalPlaces,
        receiptHeader: '',
        receiptFooter: 'Thank you for your purchase!',
        ownerUid: ownerUid,
      );
      await _db.into(_db.shops).insert(shop);
      await _db.enqueue('shops', id, shop.toJson());

      final cat = ProductCategory(
        id: newId(),
        shopId: id,
        createdAt: now,
        updatedAt: now,
        version: 1,
        syncStatus: 'pending',
        deviceId: _deviceId,
        name: 'General',
        sortOrder: 0,
      );
      await _db.into(_db.categories).insert(cat);
      await _db.enqueue('categories', cat.id, cat.toJson());
      return shop;
    });
    await _ref.read(settingsProvider.notifier).set(SettingKeys.shopId, shop.id);
    return shop;
  }

  /// Applies [change] to the shop. A new [logo] drops the old `logoUrl`; the
  /// upload queue fills it in once the shop has synced.
  Future<void> updateShop(Shop Function(Shop current) change, {ImageEdit logo = ImageEdit.keep}) {
    return _db.transaction(() async {
      final shopId = _ref.read(sessionProvider).shopId;
      final current =
          await (_db.select(_db.shops)..where((s) => s.id.equals(shopId))).getSingle();
      var changed = change(current);
      if (!logo.unchanged) {
        changed = changed.copyWith(logoLocalPath: Value(logo.localPath), logoUrl: const Value(null));
      }
      final next = changed.copyWith(
        updatedAt: nowMs(),
        version: current.version + 1,
        syncStatus: 'pending',
        deviceId: _deviceId,
      );
      await _db.update(_db.shops).replace(next);
      await _db.enqueue('shops', next.id, next.toJson());
    });
  }

  // ------------------------------------------------------------ tax rates

  Stream<List<TaxRate>> watchTaxRates() {
    final shopId = _ref.read(sessionProvider).shopId;
    return (_db.select(_db.taxRates)
          ..where((t) => t.shopId.equals(shopId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  Future<void> saveTaxRate({String? id, required String name, required int rateBps, required bool inclusive}) {
    return _db.transaction(() async {
      final session = _ref.read(sessionProvider);
      final now = nowMs();
      final existing = id == null
          ? null
          : await (_db.select(_db.taxRates)..where((t) => t.id.equals(id))).getSingleOrNull();
      final row = existing == null
          ? TaxRate(
              id: newId(),
              shopId: session.shopId,
              createdAt: now,
              updatedAt: now,
              version: 1,
              syncStatus: 'pending',
              deviceId: _deviceId,
              name: name.trim(),
              rateBps: rateBps,
              inclusive: inclusive,
            )
          : existing.copyWith(
              name: name.trim(),
              rateBps: rateBps,
              inclusive: inclusive,
              updatedAt: now,
              version: existing.version + 1,
              syncStatus: 'pending',
              deviceId: _deviceId,
            );
      await _db.into(_db.taxRates).insertOnConflictUpdate(row);
      await _db.enqueue('tax_rates', row.id, row.toJson());
    });
  }

  Future<void> deleteTaxRate(String id) {
    return _db.transaction(() async {
      final now = nowMs();
      final row = await (_db.select(_db.taxRates)..where((t) => t.id.equals(id))).getSingle();
      final deleted = row.copyWith(
        deletedAt: Value(now),
        updatedAt: now,
        version: row.version + 1,
        syncStatus: 'pending',
        deviceId: _deviceId,
      );
      await _db.update(_db.taxRates).replace(deleted);
      await _db.enqueue('tax_rates', id, deleted.toJson());
    });
  }
}

extension TaxRateSpec on TaxRate {
  TaxSpec get spec => TaxSpec(id: id, name: name, rateBps: rateBps, inclusive: inclusive);

  String get label {
    final pct = rateBps / 100;
    final text = pct == pct.roundToDouble() ? pct.toStringAsFixed(0) : pct.toString();
    return '$name $text%${inclusive ? ' (incl.)' : ''}';
  }
}

final shopRepositoryProvider = Provider<ShopRepository>(
  (ref) => ShopRepository(ref.watch(databaseProvider), ref),
);

final taxRatesProvider = StreamProvider<List<TaxRate>>(
  (ref) {
    ref.watch(sessionProvider);
    return ref.watch(shopRepositoryProvider).watchTaxRates();
  },
);
