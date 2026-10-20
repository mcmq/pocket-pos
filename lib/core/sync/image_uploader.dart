import 'dart:io';

import 'package:drift/drift.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;
import 'package:flutter/foundation.dart';

import '../data/image_store.dart';
import '../database/app_database.dart';
import '../providers/app_providers.dart';

/// The file storage the upload queue needs. [FirebaseBlobStore] is the real
/// one; tests use an in-memory fake.
abstract interface class BlobStore {
  /// Uploads [file] to [path] and returns its download URL.
  Future<String> upload(String path, File file, {String contentType = 'image/jpeg'});
}

class FirebaseBlobStore implements BlobStore {
  FirebaseBlobStore(this._storage);

  final storage.FirebaseStorage _storage;

  @override
  Future<String> upload(String path, File file, {String contentType = 'image/jpeg'}) async {
    final ref = _storage.ref(path);
    await ref.putFile(file, storage.SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }
}

/// Uploads product images and the shop logo that exist only on this device,
/// then writes the URL back as a normal row update (outbox), so other devices
/// get it through the usual sync. See docs/offline-sync.md → Images.
///
/// A row qualifies once it has synced (its document exists, so Storage rules
/// can check the shop) and has a local file but no URL yet.
class ImageUploader {
  ImageUploader({
    required this._db,
    required this._blobs,
    required this._images,
    required this._deviceId,
  });

  final AppDatabase _db;
  final BlobStore _blobs;
  final ImageStore _images;
  final String Function() _deviceId;

  /// Storage path for a row's image (docs/data-model.md → Firebase Storage).
  static String storagePath(String shopId, String rowId) => 'shops/$shopId/images/$rowId.jpg';

  /// Uploads every waiting image of [shopId]. Returns how many URLs were
  /// written back. Throws on the first failed upload; the rest retry on the
  /// next sync.
  Future<int> run(String shopId) async {
    var written = 0;

    final shops = await (_db.select(_db.shops)
          ..where((s) =>
              s.id.equals(shopId) &
              s.logoLocalPath.isNotNull() &
              s.logoUrl.isNull() &
              s.syncStatus.equals('synced')))
        .get();
    for (final shop in shops) {
      final url = await _upload(shopId, shop.id, shop.logoLocalPath!);
      if (url != null && await _writeShopUrl(shop.id, shop.logoLocalPath!, url)) written++;
    }

    final products = await (_db.select(_db.products)
          ..where((p) =>
              p.shopId.equals(shopId) &
              p.deletedAt.isNull() &
              p.imageLocalPath.isNotNull() &
              p.imageUrl.isNull() &
              p.syncStatus.equals('synced')))
        .get();
    for (final p in products) {
      final url = await _upload(shopId, p.id, p.imageLocalPath!);
      if (url != null && await _writeProductUrl(p.id, p.imageLocalPath!, url)) written++;
    }
    return written;
  }

  Future<String?> _upload(String shopId, String rowId, String localPath) async {
    final file = _images.resolve(localPath);
    if (file == null || !await file.exists()) {
      // Nothing to send (file removed outside the app). Skip, don't fail sync.
      debugPrint('Image upload skipped, missing file: $localPath');
      return null;
    }
    return _blobs.upload(storagePath(shopId, rowId), file);
  }

  /// Writes the URL unless the picture changed while uploading.
  Future<bool> _writeShopUrl(String id, String uploadedPath, String url) {
    return _db.transaction(() async {
      final shop = await (_db.select(_db.shops)..where((s) => s.id.equals(id))).getSingleOrNull();
      if (shop == null || shop.logoLocalPath != uploadedPath || shop.logoUrl != null) return false;
      final next = shop.copyWith(
        logoUrl: Value(url),
        updatedAt: nowMs(),
        version: shop.version + 1,
        syncStatus: 'pending',
        deviceId: _deviceId(),
      );
      await _db.update(_db.shops).replace(next);
      await _db.enqueue('shops', id, next.toJson());
      return true;
    });
  }

  Future<bool> _writeProductUrl(String id, String uploadedPath, String url) {
    return _db.transaction(() async {
      final p = await (_db.select(_db.products)..where((p) => p.id.equals(id))).getSingleOrNull();
      if (p == null || p.imageLocalPath != uploadedPath || p.imageUrl != null) return false;
      final next = p.copyWith(
        imageUrl: Value(url),
        updatedAt: nowMs(),
        version: p.version + 1,
        syncStatus: 'pending',
        deviceId: _deviceId(),
      );
      // Same rule as CatalogRepository: never write or sync stock_qty here.
      await (_db.update(_db.products)..where((r) => r.id.equals(id))).write(
        next.toCompanion(false).copyWith(stockQty: const Value.absent()),
      );
      await _db.enqueue('products', id, next.toJson()..remove('stockQty'));
      return true;
    });
  }
}
