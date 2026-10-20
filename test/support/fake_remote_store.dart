import 'package:pocket_pos/core/sync/remote_store.dart';

/// In-memory stand-in for Firestore with a monotonically increasing
/// server clock.
class FakeRemoteStore implements RemoteStore {
  final docs = <String, Map<String, dynamic>>{};
  final serverTimes = <String, int>{};
  int _clock = 1000;
  bool failNextCommit = false;

  @override
  Future<void> commit(List<RemoteWrite> writes) async {
    if (failNextCommit) {
      failNextCommit = false;
      throw Exception('network down');
    }
    for (final w in writes) {
      if (w.data == null) {
        docs.remove(w.path);
      } else {
        docs[w.path] = {...?docs[w.path], ...w.data!};
        serverTimes[w.path] = ++_clock;
      }
    }
  }

  @override
  Future<RemoteDoc?> get(String path) async => docs.containsKey(path) ? _doc(path) : null;

  @override
  Future<List<RemoteDoc>> changedSince(String collectionPath, int sinceMs,
      {RemoteDoc? after, required int limit}) async {
    final paths = docs.keys
        .where((p) =>
            p.startsWith('$collectionPath/') &&
            !p.substring(collectionPath.length + 1).contains('/') &&
            serverTimes[p]! > sinceMs)
        .toList()
      ..sort((a, b) => serverTimes[a]!.compareTo(serverTimes[b]!));
    var start = 0;
    if (after != null) start = paths.indexOf('$collectionPath/${after.id}') + 1;
    return [for (final p in paths.skip(start).take(limit)) _doc(p)];
  }

  @override
  Future<RemoteDoc?> findOwnedShop(String uid) async {
    for (final e in docs.entries) {
      if (RegExp(r'^shops/[^/]+$').hasMatch(e.key) && e.value['ownerUid'] == uid) {
        return _doc(e.key);
      }
    }
    return null;
  }

  RemoteDoc _doc(String path) => RemoteDoc(
        id: path.split('/').last,
        data: Map.of(docs[path]!),
        serverUpdatedMs: serverTimes[path]!,
      );
}
