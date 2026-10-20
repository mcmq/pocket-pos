import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pos/core/data/catalog_repository.dart';
import 'package:pocket_pos/core/data/image_store.dart';
import 'package:pocket_pos/core/data/shop_repository.dart';
import 'package:pocket_pos/core/database/app_database.dart';
import 'package:pocket_pos/core/providers/app_providers.dart';
import 'package:pocket_pos/core/sync/image_uploader.dart';
import 'package:pocket_pos/core/sync/sync_engine.dart';

import '../support/fake_remote_store.dart';

/// In-memory stand-in for Firebase Storage.
class FakeBlobStore implements BlobStore {
  final blobs = <String, List<int>>{};
  int uploads = 0;
  bool fail = false;

  /// Runs during an upload, to simulate edits made meanwhile.
  Future<void> Function()? during;

  @override
  Future<String> upload(String path, File file, {String contentType = 'image/jpeg'}) async {
    if (fail) throw Exception('storage down');
    await during?.call();
    uploads++;
    blobs[path] = await file.readAsBytes();
    return 'https://storage.test/$path?v=$uploads';
  }
}

AppDatabase memoryDb() =>
    AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory docs;
  late ImageStore images;

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('pocket_pos_images');
    images = ImageStore(docs);
  });

  tearDown(() => docs.delete(recursive: true));

  /// A picked photo outside the documents dir, as image_picker returns.
  Future<String> pickedPhoto([String content = 'jpeg-bytes']) async {
    final f = File('${docs.path}/picked-${content.hashCode}.jpg');
    await f.writeAsString(content);
    return f.path;
  }

  group('ImageStore', () {
    test('copies into images/ with a relative path and deletes', () async {
      final rel = await images.save(await pickedPhoto(), 'row-1');
      expect(rel, startsWith('images/row-1-'));
      final file = images.resolve(rel)!;
      expect(await file.readAsString(), 'jpeg-bytes');

      await images.delete(rel);
      expect(await file.exists(), isFalse);
      await images.delete(rel); // missing is fine
    });

    test('resolves nothing without a documents dir', () {
      expect(const ImageStore(null).resolve('images/x.jpg'), isNull);
    });
  });

  group('CatalogRepository images', () {
    late AppDatabase db;
    late CatalogRepository catalog;

    setUp(() {
      db = memoryDb();
      catalog = CatalogRepository(db, const Session(shopId: 'shop-1', deviceId: 'dev-1'));
    });

    tearDown(() => db.close());

    Future<Map<String, dynamic>> lastProductPayload() async {
      final entries = await db.select(db.outbox).get();
      return jsonDecode(entries.lastWhere((e) => e.entity == 'products').payloadJson)
          as Map<String, dynamic>;
    }

    test('a new image is stored locally, clears the URL and never syncs its path', () async {
      final p = await catalog.saveProduct(
        const ProductDraft(name: 'Tea', image: ImageEdit.set('images/a.jpg')),
      );
      expect(p.imageLocalPath, 'images/a.jpg');
      expect(p.imageUrl, isNull);
      final payload = await lastProductPayload();
      expect(payload.containsKey('imageLocalPath'), isFalse);
      expect(payload.containsKey('syncStatus'), isFalse);

      // Pretend the upload finished, then edit without touching the image.
      await (db.update(db.products)..where((r) => r.id.equals(p.id)))
          .write(const ProductsCompanion(imageUrl: Value('https://x/a.jpg')));
      final kept = await catalog.saveProduct(ProductDraft(id: p.id, name: 'Green tea'));
      expect(kept.imageLocalPath, 'images/a.jpg');
      expect(kept.imageUrl, 'https://x/a.jpg');

      final replaced = await catalog.saveProduct(
        ProductDraft(id: p.id, name: 'Green tea', image: const ImageEdit.set('images/b.jpg')),
      );
      expect(replaced.imageLocalPath, 'images/b.jpg');
      expect(replaced.imageUrl, isNull);
      expect((await lastProductPayload())['imageUrl'], isNull);

      final removed = await catalog.saveProduct(
        ProductDraft(id: p.id, name: 'Green tea', image: ImageEdit.remove),
      );
      expect(removed.imageLocalPath, isNull);
      expect(removed.imageUrl, isNull);
    });
  });

  test('ShopRepository.updateShop sets and removes the logo', () async {
    final db = memoryDb();
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      initialSettingsProvider.overrideWithValue(await loadSettings(db)),
    ]);
    addTearDown(container.dispose);
    final repo = container.read(shopRepositoryProvider);
    final shop = await repo.createShop(name: 'Corner Café', currencyCode: 'USD', currencySymbol: r'$');
    await db.update(db.shops).replace(shop.copyWith(logoUrl: const Value('https://x/old.jpg')));

    await repo.updateShop((s) => s.copyWith(phone: '555'), logo: const ImageEdit.set('images/logo.jpg'));
    var row = await db.select(db.shops).getSingle();
    expect(row.phone, '555');
    expect(row.logoLocalPath, 'images/logo.jpg');
    expect(row.logoUrl, isNull);
    final payload = jsonDecode((await db.select(db.outbox).get()).last.payloadJson) as Map;
    expect(payload.containsKey('logoLocalPath'), isFalse);

    await repo.updateShop((s) => s, logo: ImageEdit.remove);
    row = await db.select(db.shops).getSingle();
    expect(row.logoLocalPath, isNull);
  });

  group('image upload queue', () {
    const shopId = 'shop-1';
    late FakeRemoteStore remote;
    late FakeBlobStore blobs;
    late AppDatabase a;
    late AppDatabase b;
    late CatalogRepository catalogA;
    late SyncEngine engineA;
    late SyncEngine engineB;
    late ImageUploader uploaderA;

    setUp(() async {
      remote = FakeRemoteStore();
      blobs = FakeBlobStore();
      a = memoryDb();
      b = memoryDb();
      catalogA = CatalogRepository(a, const Session(shopId: shopId, deviceId: 'dev-a'));
      uploaderA = ImageUploader(db: a, blobs: blobs, images: images, deviceId: () => 'dev-a');
      engineA = SyncEngine(
        db: a,
        remote: remote,
        userId: () => 'owner-uid',
        shopId: () => shopId,
        images: uploaderA,
      );
      // Device B has no files of A's; it only ever sees the URL.
      engineB = SyncEngine(
        db: b,
        remote: remote,
        userId: () => 'owner-uid',
        shopId: () => shopId,
        images: ImageUploader(db: b, blobs: blobs, images: const ImageStore(null), deviceId: () => 'dev-b'),
      );
      final now = nowMs();
      final shop = Shop(
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
      );
      await a.into(a.shops).insert(shop);
      await a.enqueue('shops', shopId, shop.toJson());
    });

    tearDown(() async {
      await engineA.dispose();
      await engineB.dispose();
      await a.close();
      await b.close();
    });

    Future<Product> productWithImage() async {
      final rel = await images.save(await pickedPhoto(), 'p');
      return catalogA.saveProduct(ProductDraft(name: 'Latte', image: ImageEdit.set(rel)));
    }

    test('uploads after the product syncs and writes the URL back through the outbox', () async {
      final p = await productWithImage();
      // Not synced yet: nothing to upload.
      expect(await uploaderA.run(shopId), 0);

      await engineA.sync();

      expect(engineA.status.phase, SyncPhase.idle);
      final path = ImageUploader.storagePath(shopId, p.id);
      expect(path, 'shops/$shopId/images/${p.id}.jpg');
      expect(utf8.decode(blobs.blobs[path]!), 'jpeg-bytes');
      final local = (await a.select(a.products).get()).single;
      expect(local.imageUrl, startsWith('https://storage.test/$path'));
      expect(local.imageLocalPath, p.imageLocalPath);
      expect(local.syncStatus, 'synced');
      expect(await a.select(a.outbox).get(), isEmpty);

      final doc = remote.docs['shops/$shopId/products/${p.id}']!;
      expect(doc['imageUrl'], local.imageUrl);
      expect(doc.containsKey('imageLocalPath'), isFalse);
      expect(doc.containsKey('stockQty'), isFalse);

      // Another device gets the URL only.
      await engineB.sync();
      final onB = (await b.select(b.products).get()).single;
      expect(onB.imageUrl, local.imageUrl);
      expect(onB.imageLocalPath, isNull);

      // Nothing left to upload; a later pull keeps A's own file.
      await engineA.sync();
      expect(blobs.uploads, 1);
      expect((await a.select(a.products).get()).single.imageLocalPath, p.imageLocalPath);
    });

    test('uploads the shop logo', () async {
      await engineA.sync();
      final rel = await images.save(await pickedPhoto('logo'), shopId);
      final shop = await a.select(a.shops).getSingle();
      await a.transaction(() async {
        final next = shop.copyWith(logoLocalPath: Value(rel), updatedAt: nowMs(), version: shop.version + 1);
        await a.update(a.shops).replace(next);
        await a.enqueue('shops', shopId, next.toJson());
      });

      await engineA.sync();

      final path = ImageUploader.storagePath(shopId, shopId);
      expect(utf8.decode(blobs.blobs[path]!), 'logo');
      final row = await a.select(a.shops).getSingle();
      expect(row.logoUrl, startsWith('https://storage.test/$path'));
      expect(row.logoLocalPath, rel);
      expect(remote.docs['shops/$shopId']!['logoUrl'], row.logoUrl);
      expect(remote.docs['shops/$shopId']!.containsKey('logoLocalPath'), isFalse);
    });

    test('a picture changed during upload keeps the new one pending', () async {
      final p = await productWithImage();
      // Sync without uploading, so the product is synced but has no URL.
      final plain = SyncEngine(db: a, remote: remote, userId: () => 'owner-uid', shopId: () => shopId);
      addTearDown(plain.dispose);
      await plain.sync();
      final newer = await images.save(await pickedPhoto('newer'), p.id);
      blobs.during = () async {
        blobs.during = null;
        await catalogA.saveProduct(ProductDraft(id: p.id, name: 'Latte', image: ImageEdit.set(newer)));
      };

      expect(await uploaderA.run(shopId), 0);
      final row = (await a.select(a.products).get()).single;
      expect(row.imageLocalPath, newer);
      expect(row.imageUrl, isNull);
    });

    test('a missing file is skipped without failing sync', () async {
      final p = await productWithImage();
      await images.delete(p.imageLocalPath);

      await engineA.sync();

      expect(engineA.status.phase, SyncPhase.idle);
      expect(blobs.uploads, 0);
      expect((await a.select(a.products).get()).single.imageUrl, isNull);
    });

    test('a failed upload reports an error but data still syncs', () async {
      await productWithImage();
      blobs.fail = true;

      await engineA.sync();

      expect(engineA.status.phase, SyncPhase.error);
      expect(engineA.status.error, contains('storage down'));
      expect(remote.docs.keys.where((k) => k.contains('/products/')), hasLength(1));

      blobs.fail = false;
      await engineA.sync();
      expect(engineA.status.phase, SyncPhase.idle);
      expect((await a.select(a.products).get()).single.imageUrl, isNotNull);
    });

    test('a newer picture from another device replaces the local file', () async {
      final p = await productWithImage();
      await engineA.sync();
      await engineB.sync();

      // Device B swaps the picture; its upload lands under the same path.
      final catalogB = CatalogRepository(b, const Session(shopId: shopId, deviceId: 'dev-b'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final onB = (await catalogB.productById(p.id))!;
      await b.transaction(() async {
        final next = onB.copyWith(
          imageUrl: const Value('https://storage.test/from-b'),
          updatedAt: nowMs(),
          version: onB.version + 1,
        );
        await b.update(b.products).replace(next);
        await b.enqueue('products', p.id, next.toJson()..remove('stockQty'));
      });
      await engineB.sync();

      await engineA.sync();
      final onA = (await a.select(a.products).get()).single;
      expect(onA.imageUrl, 'https://storage.test/from-b');
      expect(onA.imageLocalPath, isNull);
    });
  });
}
