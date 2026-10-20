import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart' as fs show FirebaseException;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../providers/app_providers.dart';
import 'image_uploader.dart';
import 'remote_store.dart';

/// What the sync status chip shows (docs/offline-sync.md → UI states).
enum SyncPhase { disabled, signedOut, offline, idle, syncing, error }

@immutable
class SyncStatus {
  const SyncStatus(this.phase, {this.lastSyncedAt, this.error});

  final SyncPhase phase;
  final DateTime? lastSyncedAt;
  final String? error;

  SyncStatus copyWith({SyncPhase? phase, DateTime? lastSyncedAt, String? error}) =>
      SyncStatus(phase ?? this.phase, lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt, error: error);
}

/// Pushes the outbox to Firestore and pulls remote changes into SQLite.
///
/// This is the **only** code that talks to Firestore. Everything else reads
/// and writes the local DB. See docs/offline-sync.md.
class SyncEngine {
  SyncEngine({
    required this._db,
    required this._remote,
    required this._userId,
    required this._shopId,
    this._images,
    this.pushBatchSize = 400,
    this.pullPageSize = 500,
    this.maxAttempts = 10,
    this.debounce = const Duration(seconds: 2),
  });

  final AppDatabase _db;
  final RemoteStore _remote;
  final String? Function() _userId;
  final String? Function() _shopId;

  /// Image upload queue; null skips image uploads.
  final ImageUploader? _images;
  final int pushBatchSize;
  final int pullPageSize;
  final int maxAttempts;
  final Duration debounce;

  /// SQL table name → Firestore collection under `shops/{shopId}`.
  /// Order matters for pull: referenced rows first.
  static const collections = {
    'categories': 'categories',
    'tax_rates': 'taxRates',
    'parties': 'parties',
    'products': 'products',
    'transactions': 'transactions',
    'payments': 'payments',
    'stock_movements': 'stockMovements',
  };

  final _statusController = StreamController<SyncStatus>.broadcast();
  SyncStatus _status = const SyncStatus(SyncPhase.idle);
  SyncStatus get status => _status;
  Stream<SyncStatus> get statusStream => _statusController.stream;

  bool _online = true;
  bool _running = false;
  bool _rerun = false;
  Duration _backoff = const Duration(seconds: 2);
  Timer? _retryTimer;
  Timer? _debounceTimer;
  Timer? _periodic;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _remoteShopReady = <String>{};

  void _emit(SyncStatus s) {
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  /// Wires the triggers: connectivity, app resume, new outbox entries,
  /// auth changes and a periodic timer.
  void start({
    Stream<bool>? online,
    Stream<void>? resumed,
    Stream<Object?>? authChanges,
    Duration periodic = const Duration(minutes: 15),
  }) {
    if (online != null) {
      _subscriptions.add(online.listen((isOnline) {
        final cameOnline = isOnline && !_online;
        _online = isOnline;
        if (!isOnline) {
          _emit(_status.copyWith(phase: SyncPhase.offline));
        } else if (cameOnline) {
          unawaited(sync());
        }
      }));
    }
    if (resumed != null) _subscriptions.add(resumed.listen((_) => unawaited(sync())));
    if (authChanges != null) {
      _subscriptions.add(authChanges.listen((_) {
        _remoteShopReady.clear();
        unawaited(sync());
      }));
    }
    // New local changes: push shortly after, batching bursts.
    final count = _db.outbox.id.count();
    _subscriptions.add(
      (_db.selectOnly(_db.outbox)..addColumns([count]))
          .map((r) => r.read(count) ?? 0)
          .watchSingle()
          .listen((pending) {
        if (pending > 0) _schedule(debounce);
      }),
    );
    _periodic = Timer.periodic(periodic, (_) => unawaited(sync()));
    unawaited(sync());
  }

  void _schedule(Duration delay) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () => unawaited(sync()));
  }

  /// Runs one push + pull cycle. Safe to call any time; concurrent calls
  /// coalesce into one extra run.
  Future<void> sync() async {
    final uid = _userId();
    final shopId = _shopId();
    if (uid == null) {
      _emit(_status.copyWith(phase: SyncPhase.signedOut));
      return;
    }
    if (shopId == null) return;
    if (!_online) {
      _emit(_status.copyWith(phase: SyncPhase.offline));
      return;
    }
    if (_running) {
      _rerun = true;
      return;
    }
    _running = true;
    _retryTimer?.cancel();
    _emit(_status.copyWith(phase: SyncPhase.syncing));
    try {
      await _claimShop(uid, shopId);
      await _ensureRemoteShop(uid, shopId);
      await _push();
      await _pull(shopId);
      // After the pull, so a failing upload never holds back data sync.
      // Written-back URLs are ordinary row updates; push them right away.
      if (await _images?.run(shopId) case final n? when n > 0) await _push();
      final now = DateTime.now();
      await _setSetting(SettingKeys.lastSyncAt, '${now.millisecondsSinceEpoch}');
      _backoff = const Duration(seconds: 2);
      _emit(SyncStatus(SyncPhase.idle, lastSyncedAt: now));
    } catch (e, st) {
      debugPrint('Sync failed: $e\n$st');
      _emit(_status.copyWith(phase: SyncPhase.error, error: _describe(e)));
      _retryTimer = Timer(_backoff, () => unawaited(sync()));
      _backoff = Duration(
        milliseconds: math.min(_backoff.inMilliseconds * 5 ~/ 2, const Duration(minutes: 5).inMilliseconds),
      );
    } finally {
      _running = false;
    }
    if (_rerun) {
      _rerun = false;
      await sync();
    }
  }

  /// Finds a shop owned by [uid] in Firestore, copies it locally and returns
  /// its id. Used when signing in on a fresh install.
  Future<String?> adoptOwnedShop(String uid) async {
    final doc = await _remote.findOwnedShop(uid);
    if (doc == null) return null;
    await _applyRemote('shops', doc.data);
    return doc.id;
  }

  Future<void> dispose() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _retryTimer?.cancel();
    _debounceTimer?.cancel();
    _periodic?.cancel();
    await _statusController.close();
  }

  // ------------------------------------------------------------ ownership

  /// The first account that syncs a local shop becomes its owner.
  Future<void> _claimShop(String uid, String shopId) async {
    final shop = await (_db.select(_db.shops)..where((s) => s.id.equals(shopId))).getSingleOrNull();
    if (shop == null) return;
    if (shop.ownerUid == null) {
      await _db.transaction(() async {
        final next = shop.copyWith(
          ownerUid: Value(uid),
          updatedAt: nowMs(),
          version: shop.version + 1,
          syncStatus: 'pending',
        );
        await _db.update(_db.shops).replace(next);
        await _db.enqueue('shops', shopId, next.toJson());
      });
    } else if (shop.ownerUid != uid) {
      // Joining someone else's shop needs an invite (P1).
      throw const SyncException('This shop belongs to a different account.');
    }
  }

  /// Makes sure `shops/{id}` and the owner's member doc exist, so security
  /// rules allow writes to the subcollections.
  Future<void> _ensureRemoteShop(String uid, String shopId) async {
    if (_remoteShopReady.contains(shopId)) return;
    await _remote.commit([
      RemoteWrite.set('shops/$shopId', {'id': shopId, 'shopId': shopId, 'ownerUid': uid}),
      RemoteWrite.set('shops/$shopId/members/$uid', {'uid': uid, 'role': 'owner', 'active': true}),
    ]);
    _remoteShopReady.add(shopId);
  }

  // ----------------------------------------------------------------- push

  Future<void> _push() async {
    while (true) {
      final entries = await (_db.select(_db.outbox)
            ..orderBy([(o) => OrderingTerm.asc(o.id)])
            ..limit(pushBatchSize))
          .get();
      if (entries.isEmpty) return;

      final writes = <RemoteWrite>[];
      for (final e in entries) {
        final payload = jsonDecode(e.payloadJson) as Map<String, dynamic>;
        // A shop queued before sign-in has no owner yet; never push a null
        // owner over the claimed one.
        if (e.entity == 'shops' && payload['ownerUid'] == null) payload.remove('ownerUid');
        final path = docPath(e.entity, e.rowId, payload['shopId'] as String?);
        writes.add(e.op == 'delete' ? RemoteWrite.delete(path) : RemoteWrite.set(path, toRemote(payload)));
      }
      try {
        await _remote.commit(writes);
      } catch (err) {
        await _recordFailure(entries, err);
        rethrow;
      }
      await _markPushed(entries);
    }
  }

  /// Firestore path for a local row (docs/data-model.md → Firestore layout).
  static String docPath(String entity, String rowId, String? shopId) {
    if (entity == 'shops') return 'shops/$rowId';
    final collection = collections[entity];
    if (collection == null || shopId == null) {
      throw SyncException('Cannot sync $entity/$rowId');
    }
    return 'shops/$shopId/$collection/$rowId';
  }

  /// Local JSON → cloud document. The store stamps `updatedAt` with the
  /// server time (pull cursor); the client time is kept for last-write-wins.
  static Map<String, dynamic> toRemote(Map<String, dynamic> payload) =>
      {...payload, 'clientUpdatedAt': payload['updatedAt']}..remove('updatedAt');

  Future<void> _markPushed(List<OutboxEntry> entries) {
    return _db.transaction(() async {
      await (_db.delete(_db.outbox)..where((o) => o.id.isIn(entries.map((e) => e.id)))).go();
      final byEntity = <String, Set<String>>{};
      for (final e in entries) {
        byEntity.putIfAbsent(e.entity, () => {}).add(e.rowId);
      }
      for (final MapEntry(key: entity, value: ids) in byEntity.entries) {
        final table = _table(entity);
        if (table == null) continue;
        final placeholders = List.filled(ids.length, '?').join(',');
        // Rows changed again since this batch still have outbox entries and
        // stay pending.
        await _db.customUpdate(
          'UPDATE $entity SET sync_status = \'synced\' WHERE id IN ($placeholders) '
          'AND id NOT IN (SELECT row_id FROM outbox WHERE table_name = ?)',
          variables: [for (final id in ids) Variable.withString(id), Variable.withString(entity)],
          updates: {table},
        );
      }
    });
  }

  Future<void> _recordFailure(List<OutboxEntry> entries, Object error) {
    final message = _describe(error);
    return _db.transaction(() async {
      for (final e in entries) {
        final attempts = e.attempts + 1;
        await (_db.update(_db.outbox)..where((o) => o.id.equals(e.id))).write(
          OutboxCompanion(attempts: Value(attempts), lastError: Value(message)),
        );
        final table = _table(e.entity);
        if (attempts >= maxAttempts && table != null) {
          await _db.customUpdate(
            'UPDATE ${e.entity} SET sync_status = \'error\' WHERE id = ?',
            variables: [Variable.withString(e.rowId)],
            updates: {table},
          );
        }
      }
    });
  }

  // ----------------------------------------------------------------- pull

  Future<void> _pull(String shopId) async {
    final shopDoc = await _remote.get('shops/$shopId');
    if (shopDoc != null && shopDoc.data.containsKey('name')) {
      await _applyRemote('shops', shopDoc.data);
    }

    for (final MapEntry(key: entity, value: collection) in collections.entries) {
      final cursorKey = SettingKeys.cursor(collection);
      final cursor = int.tryParse(await _getSetting(cursorKey) ?? '') ?? 0;
      var maxSeen = cursor;
      RemoteDoc? last;
      while (true) {
        final page = await _remote.changedSince(
          'shops/$shopId/$collection',
          cursor,
          after: last,
          limit: pullPageSize,
        );
        for (final doc in page) {
          await _applyRemote(entity, doc.data);
          maxSeen = math.max(maxSeen, doc.serverUpdatedMs);
        }
        if (page.length < pullPageSize) break;
        last = page.last;
      }
      if (maxSeen != cursor) await _setSetting(cursorKey, '$maxSeen');
    }
  }

  /// Upserts one remote document locally using last-write-wins on the
  /// client `updatedAt`. Stock is recomputed from movements, never copied.
  Future<void> _applyRemote(String entity, Map<String, dynamic> data) async {
    final json = Map<String, dynamic>.of(data);
    json['updatedAt'] = ((json.remove('clientUpdatedAt') ?? 0) as num).toInt();
    json['syncStatus'] = 'synced';
    final items = json.remove('items') as List?;
    final id = json['id'] as String;
    final remoteUpdated = json['updatedAt'] as int;

    final extra = switch (entity) {
      'products' => ', stock_qty, image_local_path, image_url',
      'shops' => ', logo_local_path, logo_url',
      _ => '',
    };
    final local = await _db
        .customSelect(
          'SELECT updated_at$extra FROM $entity WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    if (local != null && local.read<int>('updated_at') >= remoteUpdated) return;

    // Local image files aren't synced. Keep ours while the remote row still
    // points at the same upload (or neither has one yet); a different URL
    // means another device changed the picture.
    void keepLocalImage(String pathKey, String pathColumn, String urlKey, String urlColumn) {
      if (local == null) return;
      final path = local.readNullable<String>(pathColumn);
      if (path != null && local.readNullable<String>(urlColumn) == json[urlKey]) json[pathKey] = path;
    }

    // Upserts below use toCompanion(false) so remote nulls clear local values.
    await _db.transaction(() async {
      // Remote is newer: drop any older local change still queued.
      await (_db.delete(_db.outbox)..where((o) => o.entity.equals(entity) & o.rowId.equals(id))).go();

      switch (entity) {
        case 'shops':
          keepLocalImage('logoLocalPath', 'logo_local_path', 'logoUrl', 'logo_url');
          await _db.into(_db.shops).insertOnConflictUpdate(Shop.fromJson(json).toCompanion(false));
        case 'categories':
          await _db.into(_db.categories).insertOnConflictUpdate(ProductCategory.fromJson(json).toCompanion(false));
        case 'tax_rates':
          await _db.into(_db.taxRates).insertOnConflictUpdate(TaxRate.fromJson(json).toCompanion(false));
        case 'parties':
          await _db.into(_db.parties).insertOnConflictUpdate(Party.fromJson(json).toCompanion(false));
        case 'products':
          json['stockQty'] = local?.read<double>('stock_qty') ?? 0.0;
          keepLocalImage('imageLocalPath', 'image_local_path', 'imageUrl', 'image_url');
          await _db.into(_db.products).insertOnConflictUpdate(Product.fromJson(json).toCompanion(false));
          await _db.recomputeStock(id);
        case 'transactions':
          await _db.into(_db.transactions).insertOnConflictUpdate(Txn.fromJson(json).toCompanion(false));
          await (_db.delete(_db.transactionItems)..where((i) => i.transactionId.equals(id))).go();
          for (final item in items ?? const []) {
            await _db.into(_db.transactionItems).insert(
                  TxnItem.fromJson(Map<String, dynamic>.from(item as Map)),
                );
          }
        case 'payments':
          await _db.into(_db.payments).insertOnConflictUpdate(Payment.fromJson(json).toCompanion(false));
        case 'stock_movements':
          final m = StockMovement.fromJson(json);
          await _db.into(_db.stockMovements).insertOnConflictUpdate(m.toCompanion(false));
          await _db.recomputeStock(m.productId);
      }
    });
  }

  // -------------------------------------------------------------- helpers

  TableInfo<Table, Object?>? _table(String entity) {
    for (final t in _db.allTables) {
      if (t.actualTableName == entity) return t;
    }
    return null;
  }

  Future<String?> _getSetting(String key) async =>
      (await (_db.select(_db.settings)..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Future<void> _setSetting(String key, String value) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));

  static String _describe(Object e) {
    if (e is SyncException) return e.message;
    if (e is fs.FirebaseException) {
      return switch (e.code) {
        'permission-denied' => 'Permission denied by the server.',
        'unavailable' => 'Server unreachable. Will retry.',
        'unauthenticated' => 'Please sign in again.',
        _ => e.message ?? e.code,
      };
    }
    return e.toString();
  }
}

class SyncException implements Exception {
  const SyncException(this.message);
  final String message;

  @override
  String toString() => message;
}
