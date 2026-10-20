import 'package:drift/drift.dart';

/// Columns every synced table carries (docs/data-model.md → Conventions).
mixin SyncColumns on Table {
  TextColumn get id => text()();
  TextColumn get shopId => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  /// `pending` / `synced` / `error`. Local only, never uploaded.
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  TextColumn get deviceId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Shops extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get phone => text().withDefault(const Constant(''))();
  TextColumn get address => text().withDefault(const Constant(''))();
  TextColumn get taxId => text().withDefault(const Constant(''))();
  TextColumn get currencyCode => text().withDefault(const Constant('USD'))();
  TextColumn get currencySymbol => text().withDefault(const Constant(r'$'))();

  /// `start` / `end`.
  TextColumn get currencyPosition =>
      text().withDefault(const Constant('start'))();
  IntColumn get decimalPlaces => integer().withDefault(const Constant(2))();
  TextColumn get logoUrl => text().nullable()();

  /// Logo file relative to the app documents dir. Device only, never synced.
  TextColumn get logoLocalPath => text().nullable()();
  TextColumn get receiptHeader => text().withDefault(const Constant(''))();
  TextColumn get receiptFooter =>
      text().withDefault(const Constant('Thank you for your purchase!'))();
  TextColumn get ownerUid => text().nullable()();
}

@DataClassName('ProductCategory')
@TableIndex(name: 'categories_shop_sort', columns: {#shopId, #sortOrder})
class Categories extends Table with SyncColumns {
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get color => text().nullable()();
}

@TableIndex(name: 'products_shop_name', columns: {#shopId, #name})
@TableIndex(name: 'products_shop_barcode', columns: {#shopId, #barcode})
@TableIndex(name: 'products_shop_sku', columns: {#shopId, #sku})
class Products extends Table with SyncColumns {
  TextColumn get categoryId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get sku => text().nullable()();
  TextColumn get barcode => text().nullable()();
  TextColumn get unit => text().withDefault(const Constant('pcs'))();
  TextColumn get imageUrl => text().nullable()();

  /// Image file relative to the app documents dir. Device only, never synced.
  TextColumn get imageLocalPath => text().nullable()();
  IntColumn get salePriceMinor => integer().withDefault(const Constant(0))();
  IntColumn get purchasePriceMinor => integer().withDefault(const Constant(0))();
  TextColumn get taxRateId => text().nullable()();

  /// Cached `SUM(stock_movements.qty_delta)`. Never synced as an absolute.
  RealColumn get stockQty => real().withDefault(const Constant(0))();
  RealColumn get lowStockThreshold => real().withDefault(const Constant(0))();
  BoolColumn get trackStock => boolean().withDefault(const Constant(true))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
}

@TableIndex(name: 'parties_shop_name', columns: {#shopId, #name})
class Parties extends Table with SyncColumns {
  /// `customer` / `supplier` / `both`.
  TextColumn get type => text().withDefault(const Constant('customer'))();
  TextColumn get name => text()();
  TextColumn get phone => text().withDefault(const Constant(''))();
  TextColumn get email => text().withDefault(const Constant(''))();
  TextColumn get address => text().withDefault(const Constant(''))();
  IntColumn get openingBalanceMinor => integer().withDefault(const Constant(0))();
}

class TaxRates extends Table with SyncColumns {
  TextColumn get name => text()();

  /// Basis points: 1500 = 15%.
  IntColumn get rateBps => integer()();
  BoolColumn get inclusive => boolean().withDefault(const Constant(false))();
}

/// One table for every document type (sale, payment_in, …).
@DataClassName('Txn')
@TableIndex(name: 'transactions_shop_date', columns: {#shopId, #date})
@TableIndex(name: 'transactions_party', columns: {#partyId})
class Transactions extends Table with SyncColumns {
  /// sale | sale_return | quotation | payment_in | purchase | purchase_return |
  /// payment_out | expense | transfer
  TextColumn get type => text()();

  /// Display number, e.g. `A-0012`.
  TextColumn get number => text()();
  IntColumn get deviceSeq => integer().withDefault(const Constant(0))();

  /// Invoice date, ms epoch UTC.
  IntColumn get date => integer()();
  TextColumn get partyId => text().nullable()();
  IntColumn get subtotalMinor => integer().withDefault(const Constant(0))();
  IntColumn get discountMinor => integer().withDefault(const Constant(0))();
  IntColumn get taxMinor => integer().withDefault(const Constant(0))();
  IntColumn get chargesMinor => integer().withDefault(const Constant(0))();
  IntColumn get totalMinor => integer().withDefault(const Constant(0))();
  IntColumn get paidMinor => integer().withDefault(const Constant(0))();

  /// paid | partial | unpaid | void
  TextColumn get status => text()();
  TextColumn get paymentMode => text().withDefault(const Constant('cash'))();
  TextColumn get notes => text().withDefault(const Constant(''))();

  /// Snapshot of applied taxes and charges for receipts:
  /// `{"taxes": [{name, rateBps, inclusive, amountMinor}],
  ///   "charges": [{label, amountMinor}]}`.
  TextColumn get breakdownJson => text().withDefault(const Constant('{}'))();
  TextColumn get refTransactionId => text().nullable()();
  TextColumn get createdBy => text().nullable()();
}

/// Lines of a transaction. Synced embedded in the transaction document.
@DataClassName('TxnItem')
@TableIndex(name: 'transaction_items_txn', columns: {#transactionId})
class TransactionItems extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId => text()();
  TextColumn get productId => text().nullable()();
  TextColumn get nameSnapshot => text()();
  TextColumn get unitSnapshot => text().withDefault(const Constant('pcs'))();
  RealColumn get qty => real()();
  IntColumn get unitPriceMinor => integer()();
  IntColumn get discountMinor => integer().withDefault(const Constant(0))();
  IntColumn get taxMinor => integer().withDefault(const Constant(0))();
  IntColumn get lineTotalMinor => integer()();
  IntColumn get costPriceMinor => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'payments_txn', columns: {#transactionId})
class Payments extends Table with SyncColumns {
  TextColumn get transactionId => text().nullable()();
  TextColumn get partyId => text().nullable()();

  /// `in` / `out`.
  TextColumn get direction => text()();
  IntColumn get amountMinor => integer()();

  /// cash | card | mobile_money | bank | other
  TextColumn get mode => text()();
  TextColumn get reference => text().withDefault(const Constant(''))();
  IntColumn get date => integer()();
}

/// Append-only stock deltas. `products.stock_qty` = SUM(qty_delta).
@TableIndex(name: 'stock_movements_product', columns: {#productId})
class StockMovements extends Table with SyncColumns {
  TextColumn get productId => text()();
  RealColumn get qtyDelta => real()();

  /// sale | sale_return | purchase | purchase_return | adjustment | opening | void
  TextColumn get reason => text()();
  TextColumn get transactionId => text().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
}

/// Local-only queue of changes waiting to be pushed to Firestore.
@DataClassName('OutboxEntry')
class Outbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entity => text().named('table_name')();
  TextColumn get rowId => text()();

  /// `upsert` / `delete`.
  TextColumn get op => text()();
  TextColumn get payloadJson => text()();
  IntColumn get createdAt => integer()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}

/// Local-only key/value device preferences.
@DataClassName('SettingEntry')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
