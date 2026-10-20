import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_service.dart';
import '../data/image_store.dart';
import '../providers/app_providers.dart';
import 'image_uploader.dart';
import 'remote_store.dart';
import 'sync_engine.dart';

/// The running sync engine, or null when Firebase isn't configured.
final syncEngineProvider = Provider<SyncEngine?>((ref) {
  if (!ref.watch(firebaseReadyProvider)) return null;
  final auth = ref.watch(authServiceProvider);
  final db = ref.watch(databaseProvider);
  final engine = SyncEngine(
    db: db,
    remote: FirestoreRemoteStore(fs.FirebaseFirestore.instance),
    userId: () => auth.currentUser?.uid,
    shopId: () => ref.read(shopIdProvider),
    images: ImageUploader(
      db: db,
      blobs: FirebaseBlobStore(FirebaseStorage.instance),
      images: ref.watch(imageStoreProvider),
      deviceId: () => ref.read(settingsProvider)[SettingKeys.deviceId]!,
    ),
  );

  final resumed = StreamController<void>.broadcast();
  final lifecycle = AppLifecycleListener(onResume: () => resumed.add(null));
  final connectivity = Connectivity()
      .onConnectivityChanged
      .map((results) => results.any((r) => r != ConnectivityResult.none));

  engine.start(online: connectivity, resumed: resumed.stream, authChanges: auth.authStateChanges());

  // Sync as soon as a shop is created or adopted.
  ref.listen(shopIdProvider, (_, next) {
    if (next != null) unawaited(engine.sync());
  });

  ref.onDispose(() {
    lifecycle.dispose();
    resumed.close();
    engine.dispose();
  });
  return engine;
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final engine = ref.watch(syncEngineProvider);
  if (engine == null) return Stream.value(const SyncStatus(SyncPhase.disabled));
  return Stream.multi((controller) {
    controller.add(engine.status);
    final sub = engine.statusStream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
});
