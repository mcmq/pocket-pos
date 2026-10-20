import 'package:cloud_firestore/cloud_firestore.dart' as fs;

/// A document read from the cloud.
class RemoteDoc {
  const RemoteDoc({required this.id, required this.data, required this.serverUpdatedMs});

  final String id;

  /// Document fields, with the client `updatedAt` under `clientUpdatedAt`.
  final Map<String, dynamic> data;

  /// Server write time, used as the pull cursor.
  final int serverUpdatedMs;
}

/// One write in a batch. `data == null` deletes the document.
class RemoteWrite {
  const RemoteWrite.set(this.path, Map<String, dynamic> this.data);
  const RemoteWrite.delete(this.path) : data = null;

  final String path;
  final Map<String, dynamic>? data;
}

/// The cloud operations the sync engine needs. [FirestoreRemoteStore] is the
/// real one; tests use an in-memory fake.
abstract interface class RemoteStore {
  /// Applies [writes] atomically. Set-writes merge and stamp a server
  /// `updatedAt`.
  Future<void> commit(List<RemoteWrite> writes);

  Future<RemoteDoc?> get(String path);

  /// Documents in [collectionPath] written after [sinceMs] (server time),
  /// oldest first. Pass the last doc of a page as [after] to continue.
  Future<List<RemoteDoc>> changedSince(
    String collectionPath,
    int sinceMs, {
    RemoteDoc? after,
    required int limit,
  });

  /// A shop document whose `ownerUid` is [uid], if any.
  Future<RemoteDoc?> findOwnedShop(String uid);
}

class FirestoreRemoteStore implements RemoteStore {
  FirestoreRemoteStore(this._fs);

  final fs.FirebaseFirestore _fs;

  /// Firestore cursors need the snapshot, so keep the last page's ones.
  final _snapshots = <String, fs.DocumentSnapshot<Map<String, dynamic>>>{};

  @override
  Future<void> commit(List<RemoteWrite> writes) async {
    final batch = _fs.batch();
    for (final w in writes) {
      final ref = _fs.doc(w.path);
      final data = w.data;
      if (data == null) {
        batch.delete(ref);
      } else {
        batch.set(
          ref,
          {...data, 'updatedAt': fs.FieldValue.serverTimestamp()},
          fs.SetOptions(merge: true),
        );
      }
    }
    await batch.commit();
  }

  @override
  Future<RemoteDoc?> get(String path) async {
    final snap = await _fs.doc(path).get();
    return snap.exists ? _toDoc(snap) : null;
  }

  @override
  Future<List<RemoteDoc>> changedSince(
    String collectionPath,
    int sinceMs, {
    RemoteDoc? after,
    required int limit,
  }) async {
    var query = _fs
        .collection(collectionPath)
        .where('updatedAt', isGreaterThan: fs.Timestamp.fromMillisecondsSinceEpoch(sinceMs))
        .orderBy('updatedAt')
        .limit(limit);
    final cursor = after == null ? null : _snapshots['$collectionPath/${after.id}'];
    if (cursor != null) query = query.startAfterDocument(cursor);
    final page = await query.get();
    _snapshots.removeWhere((key, _) => key.startsWith('$collectionPath/'));
    if (page.docs.isNotEmpty) {
      _snapshots['$collectionPath/${page.docs.last.id}'] = page.docs.last;
    }
    return [for (final d in page.docs) _toDoc(d)];
  }

  @override
  Future<RemoteDoc?> findOwnedShop(String uid) async {
    final snap = await _fs.collection('shops').where('ownerUid', isEqualTo: uid).limit(1).get();
    return snap.docs.isEmpty ? null : _toDoc(snap.docs.first);
  }

  static RemoteDoc _toDoc(fs.DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = Map<String, dynamic>.of(snap.data() ?? const {});
    final ts = data.remove('updatedAt');
    return RemoteDoc(
      id: snap.id,
      data: data,
      serverUpdatedMs: ts is fs.Timestamp ? ts.millisecondsSinceEpoch : 0,
    );
  }
}
