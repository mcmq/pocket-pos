import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Shops,
    Categories,
    Products,
    Parties,
    TaxRates,
    Transactions,
    TransactionItems,
    Payments,
    StockMovements,
    Outbox,
    Settings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'pocket_pos'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.addColumn(shops, shops.logoLocalPath);
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Row fields that stay on this device: they are stripped from outbox
  /// payloads and kept as-is when a remote change is pulled.
  static const localOnlyFields = {'syncStatus', 'imageLocalPath', 'logoLocalPath'};

  /// Queues a change for the sync engine. Must be called inside the same
  /// `transaction(...)` as the write it describes.
  Future<void> enqueue(
    String entity,
    String rowId,
    Map<String, dynamic> payload, {
    String op = 'upsert',
  }) {
    final clean = Map<String, dynamic>.of(payload)..removeWhere((k, _) => localOnlyFields.contains(k));
    return into(outbox).insert(
      OutboxCompanion.insert(
        entity: entity,
        rowId: rowId,
        op: op,
        payloadJson: jsonEncode(clean),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Rebuilds `products.stock_qty` from its stock movements.
  Future<void> recomputeStock(String productId) async {
    await customUpdate(
      'UPDATE products SET stock_qty = '
      '(SELECT COALESCE(SUM(qty_delta), 0) FROM stock_movements '
      'WHERE product_id = ?1 AND deleted_at IS NULL) WHERE id = ?1',
      variables: [Variable.withString(productId)],
      updates: {products},
    );
  }

  /// Integrity check: rebuilds every cached stock value.
  Future<void> recomputeAllStock() => customUpdate(
        'UPDATE products SET stock_qty = '
        '(SELECT COALESCE(SUM(qty_delta), 0) FROM stock_movements m '
        'WHERE m.product_id = products.id AND m.deleted_at IS NULL)',
        updates: {products},
      );
}
