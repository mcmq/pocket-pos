import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pos/core/data/catalog_repository.dart';
import 'package:pocket_pos/core/data/sale_draft.dart';
import 'package:pocket_pos/core/data/sales_repository.dart';
import 'package:pocket_pos/core/database/app_database.dart';
import 'package:pocket_pos/core/providers/app_providers.dart';
import 'package:pocket_pos/core/utils/period.dart';

void main() {
  late AppDatabase db;
  late CatalogRepository catalog;
  late SalesRepository sales;
  const session = Session(shopId: 'shop-1', deviceId: 'dev-1');

  setUp(() {
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    catalog = CatalogRepository(db, session);
    sales = SalesRepository(db, session);
  });

  tearDown(() => db.close());

  Future<Product> product({double stock = 10, int price = 450}) => catalog.saveProduct(
        ProductDraft(name: 'Coffee', salePriceMinor: price, purchasePriceMinor: 200),
        openingStock: stock,
      );

  Future<List<OutboxEntry>> outbox() => db.select(db.outbox).get();

  test('opening stock writes a movement and cached stock', () async {
    final p = await product(stock: 10);
    expect(p.stockQty, 10);
    final moves = await catalog.watchMovements(p.id).first;
    expect(moves.single.reason, 'opening');
    final entities = (await outbox()).map((e) => e.entity).toSet();
    expect(entities, {'products', 'stock_movements'});
    // Stock never syncs as an absolute value.
    final productPayload = jsonDecode(
      (await outbox()).firstWhere((e) => e.entity == 'products').payloadJson,
    ) as Map;
    expect(productPayload.containsKey('stockQty'), isFalse);
    expect(productPayload.containsKey('syncStatus'), isFalse);
  });

  test('completeSale writes txn, items, stock, payment and outbox atomically', () async {
    final p = await product(stock: 10);
    await db.delete(db.outbox).go();

    final txn = await sales.completeSale(SaleDraft(
      date: DateTime(2026, 2, 3),
      lines: [SaleLine(productId: p.id, name: p.name, qty: 3, unitPriceMinor: 450)],
    ));

    expect(txn.number, 'A-0001');
    expect(txn.totalMinor, 1350);
    expect(txn.status, 'paid');
    expect((await catalog.productById(p.id))!.stockQty, 7);

    final detail = (await sales.detail(txn.id))!;
    expect(detail.items.single.qty, 3);
    expect(detail.payments.single.amountMinor, 1350);

    final entities = (await outbox()).map((e) => e.entity).toList();
    expect(entities, containsAll(['transactions', 'stock_movements', 'payments']));
    final txnPayload = jsonDecode(
      (await outbox()).firstWhere((e) => e.entity == 'transactions').payloadJson,
    ) as Map;
    expect((txnPayload['items'] as List).length, 1);

    final second = await sales.completeSale(SaleDraft(
      date: DateTime(2026, 2, 3),
      lines: [SaleLine(productId: p.id, name: p.name, qty: 1, unitPriceMinor: 450)],
    ));
    expect(second.number, 'A-0002');
  });

  test('a failing sale leaves nothing behind', () async {
    final p = await product(stock: 5);
    await db.delete(db.outbox).go();
    await db.customStatement(
      "CREATE TRIGGER fail_payments BEFORE INSERT ON payments BEGIN SELECT RAISE(ABORT, 'boom'); END",
    );

    await expectLater(
      sales.completeSale(SaleDraft(
        date: DateTime(2026),
        lines: [SaleLine(productId: p.id, name: p.name, qty: 2, unitPriceMinor: 450)],
      )),
      throwsA(anything),
    );

    expect(await db.select(db.transactions).get(), isEmpty);
    expect(await db.select(db.transactionItems).get(), isEmpty);
    expect((await catalog.productById(p.id))!.stockQty, 5);
    expect(await outbox(), isEmpty);
  });

  test('credit sale then payment in updates status', () async {
    final p = await product();
    final txn = await sales.completeSale(SaleDraft(
      date: DateTime(2026),
      lines: [SaleLine(productId: p.id, name: p.name, qty: 2, unitPriceMinor: 500)],
      paymentMode: PaymentMode.credit,
    ));
    expect(txn.status, 'unpaid');

    await sales.receivePayment(saleId: txn.id, amountMinor: 400, mode: PaymentMode.cash);
    var sale = (await sales.detail(txn.id))!.txn;
    expect(sale.paidMinor, 400);
    expect(sale.status, 'partial');

    await sales.receivePayment(saleId: txn.id, amountMinor: 600, mode: PaymentMode.card);
    sale = (await sales.detail(txn.id))!.txn;
    expect(sale.status, 'paid');
  });

  test('void reverses stock and excludes the sale from the summary', () async {
    final p = await product(stock: 10);
    final txn = await sales.completeSale(SaleDraft(
      date: DateTime.now(),
      lines: [SaleLine(productId: p.id, name: p.name, qty: 4, unitPriceMinor: 450)],
    ));
    expect((await catalog.productById(p.id))!.stockQty, 6);
    expect((await sales.watchSummary(Period.allTime).first).count, 1);

    await sales.voidTransaction(txn.id);

    expect((await catalog.productById(p.id))!.stockQty, 10);
    final detail = (await sales.detail(txn.id))!;
    expect(detail.txn.status, 'void');
    expect(detail.payments, isEmpty);
    expect((await sales.watchSummary(Period.allTime).first).count, 0);
    // Rows are never hard-deleted.
    expect(await db.select(db.payments).get(), hasLength(1));
  });

  test('stock may go negative instead of blocking a sale', () async {
    final p = await product(stock: 1);
    await sales.completeSale(SaleDraft(
      date: DateTime(2026),
      lines: [SaleLine(productId: p.id, name: p.name, qty: 3, unitPriceMinor: 450)],
    ));
    expect((await catalog.productById(p.id))!.stockQty, -2);
  });

  test('search and low-stock filters', () async {
    await catalog.saveProduct(const ProductDraft(name: 'Green Tea', sku: 'GT-1', barcode: '123'));
    await catalog.saveProduct(
      const ProductDraft(name: 'Muffin', lowStockThreshold: 5),
      openingStock: 2,
    );
    expect((await catalog.watchProducts(query: 'tea').first).single.name, 'Green Tea');
    expect((await catalog.watchProducts(query: '123').first).single.name, 'Green Tea');
    expect((await catalog.watchProducts(query: 'gt-1').first).single.name, 'Green Tea');
    final low = await catalog.watchProducts(lowStockOnly: true).first;
    expect(low.map((p) => p.name), containsAll(['Muffin', 'Green Tea']));
    expect(
      () => catalog.saveProduct(const ProductDraft(name: 'Other', barcode: '123')),
      throwsA(isA<DuplicateBarcodeException>()),
    );
  });
}
