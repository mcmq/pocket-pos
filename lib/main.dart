import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/config/firebase_options.dart';
import 'core/data/image_store.dart';
import 'core/database/app_database.dart' show AppDatabase;
import 'core/providers/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Env.load();

  // The app is offline-first: it still runs on local SQLite if Firebase
  // isn't configured yet. Sync stays disabled until it is.
  final firebaseReady = await _initFirebase();

  final db = AppDatabase();
  final settings = await loadSettings(db);
  final documents = await getApplicationDocumentsDirectory();

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        initialSettingsProvider.overrideWithValue(settings),
        firebaseReadyProvider.overrideWithValue(firebaseReady),
        imageStoreProvider.overrideWithValue(ImageStore(documents)),
      ],
      child: const PocketPosApp(),
    ),
  );
}

Future<bool> _initFirebase() async {
  if (!Env.isFirebaseConfigured) {
    debugPrint('Firebase not configured — fill in .env (see docs/setup.md).');
    return false;
  }
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // SQLite is our cache; a second Firestore cache would conflict.
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);
    if (Env.useFirebaseEmulator) {
      final host = Platform.isAndroid ? '10.0.2.2' : 'localhost';
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
      await FirebaseAuth.instance.useAuthEmulator(host, 9099);
      await FirebaseStorage.instance.useStorageEmulator(host, 9199);
    }
    return true;
  } catch (e) {
    debugPrint('Firebase init failed, running local-only: $e');
    return false;
  }
}
