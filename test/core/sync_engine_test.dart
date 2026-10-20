import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pos/core/data/catalog_repository.dart';
import 'package:pocket_pos/core/data/sale_draft.dart';
import 'package:pocket_pos/core/data/sales_repository.dart';
import 'package:pocket_pos/core/database/app_database.dart';
import 'package:pocket_pos/core/providers/app_providers.dart';
import 'package:pocket_pos/core/sync/sync_engine.dart';

import '../support/fake_remote_store.dart';

class Device {
  Device(this.remote, String deviceId, String shopId)
      : db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true)) {
    final session = Session(shopId: shopId, deviceId: deviceId);
    catalog = CatalogRepository(db, session);
    sales = SalesRepository(db, session);
    engine = SyncEngine(
      db: db,
      remote: remote,
      userId: () => 'owner-uid',
      shopId: () => shopId,
      pushBatchSize: 3,
      pullPageSize: 2,
    );
  }

  final FakeRemoteStore remote;
  final AppDatabase db;
  late final CatalogRepository catalog;
  late final SalesRepository sales;
  late final SyncEngine engine;

  Future<int> pending() async => (await db.select(db.outbox).get()).length;
}

void main() {
  late FakeRemoteStore remote;
  late Device a;
  late Device b;
  const shopId = 'shop-1';

  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUp(() async {
    remote = FakeRemoteStore();
    a = Device(remote, 'dev-a', shopId);
    b = Device(remote, 'dev-b', shopId);
    final now = nowMs();
    await a.db.into(a.db.shops).insert(Shop(
          id: shopId,
          shopId: shopId,
          createdAt: now,
          updatedAt: now,
          version: 1,
          syncStatus: 'pending',
          deviceId: 'dev-a',
          name: 'Corner Café',
          phone: '',
          address: '',
          taxId: '',
          currencyCode: 'USD',
          currencySymbol: r'$',
          currencyPosition: 'start',
          decimalPlaces: 2,
          receiptHeader: '',
          receiptFooter: '',
        ));
    await a.db.enqueue('shops', shopId, (await a.db.select(a.db.shops).getSingle()).toJson());
  });

  tearDown(() async {
    await a.engine.dispose();
    await b.engine.dispose();
    await a.db.close();
    await b.db.close();
  });

  test('push drains the outbox in batches and marks rows synced', () async {
    for (var i = 0; i < 4; i++) {
      await a.catalog.saveProduct(ProductDraft(name: 'Item $i', salePriceMinor: 100), openingStock: 5);
    }
    expect(await a.pending(), greaterThan(3));

    await a.engine.sync();

    expect(a.engine.status.phase, SyncPhase.idle);
    expect(await a.pending(), 0);
    final products = await a.db.select(a.db.products).get();
    expect(products.every((p) => p.syncStatus == 'synced'), isTrue);
    // The shop row queued before sign-in (ownerUid null) must not clear it.
    expect(remote.docs['shops/$shopId']!['ownerUid'], 'owner-uid');
    expect(remote.docs['shops/$shopId']!['name'], 'Corner Café');
    expect(remote.docs.containsKey('shops/$shopId/members/owner-uid'), isTrue);
    final productDoc = remote.docs['shops/$shopId/products/${products.first.id}']!;
    expect(productDoc.containsKey('stockQty'), isFalse);
    expect(productDoc['clientUpdatedAt'], products.first.updatedAt);
  });

  test('two devices selling the same item offline merge stock by deltas', () async {
    final p = await a.catalog.saveProduct(
      const ProductDraft(name: 'Croissant', salePriceMinor: 300),
      openingStock: 10,
    );
    await a.engine.sync();
    await b.engine.sync();
    expect((await b.catalog.productById(p.id))!.stockQty, 10);

    // Both sell while offline.
    SaleDraft sale(double qty) => SaleDraft(
          date: DateTime(2026, 3, 1),
          lines: [SaleLine(productId: p.id, name: p.name, qty: qty, unitPriceMinor: 300)],
        );
    await a.sales.completeSale(sale(3));
    await b.sales.completeSale(sale(2));

    await a.engine.sync();
    await b.engine.sync();
    await a.engine.sync();

    expect((await a.catalog.productById(p.id))!.stockQty, 5);
    expect((await b.catalog.productById(p.id))!.stockQty, 5);

    final txnsOnA = await a.db.select(a.db.transactions).get();
    expect(txnsOnA, hasLength(2));
    final itemsOnA = await a.db.select(a.db.transactionItems).get();
    expect(itemsOnA, hasLength(2));
  });

  test('last write wins on product edits', () async {
    final p = await a.catalog.saveProduct(const ProductDraft(name: 'Tea', salePriceMinor: 200));
    await a.engine.sync();
    await b.engine.sync();

    await a.catalog.saveProduct(ProductDraft(id: p.id, name: 'Tea (A)', salePriceMinor: 200));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await b.catalog.saveProduct(ProductDraft(id: p.id, name: 'Tea (B)', salePriceMinor: 250));

    await a.engine.sync();
    await b.engine.sync();
    await a.engine.sync();

    expect((await a.catalog.productById(p.id))!.name, 'Tea (B)');
    expect((await b.catalog.productById(p.id))!.name, 'Tea (B)');
  });

  test('a failed push keeps the outbox and records the error', () async {
    await a.engine.sync();
    await a.catalog.saveProduct(const ProductDraft(name: 'Juice'));
    remote.failNextCommit = true;

    await a.engine.sync();

    expect(a.engine.status.phase, SyncPhase.error);
    final entries = await a.db.select(a.db.outbox).get();
    expect(entries, isNotEmpty);
    expect(entries.first.attempts, 1);
    expect(entries.first.lastError, contains('network down'));
  });

  test('a fresh install adopts the shop owned by the account', () async {
    await a.catalog.saveProduct(const ProductDraft(name: 'Bagel'));
    await a.engine.sync();

    final fresh = Device(remote, 'dev-c', shopId);
    addTearDown(() async {
      await fresh.engine.dispose();
      await fresh.db.close();
    });
    expect(await fresh.engine.adoptOwnedShop('owner-uid'), shopId);
    await fresh.engine.sync();
    expect((await fresh.db.select(fresh.db.shops).getSingle()).name, 'Corner Café');
    expect((await fresh.db.select(fresh.db.products).get()).single.name, 'Bagel');
  });

  test('signed out does nothing', () async {
    final engine = SyncEngine(db: a.db, remote: remote, userId: () => null, shopId: () => shopId);
    addTearDown(engine.dispose);
    await engine.sync();
    expect(engine.status.phase, SyncPhase.signedOut);
    expect(remote.docs, isEmpty);
  });
}
