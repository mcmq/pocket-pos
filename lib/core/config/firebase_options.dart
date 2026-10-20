import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'env.dart';

/// Firebase options built from `.env` instead of a committed,
/// FlutterFire-generated file.
abstract final class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('PocketPOS does not target web.');
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => FirebaseOptions(
        apiKey: Env.firebaseAndroidApiKey,
        appId: Env.firebaseAndroidAppId,
        messagingSenderId: Env.firebaseMessagingSenderId,
        projectId: Env.firebaseProjectId,
        storageBucket: Env.firebaseStorageBucket,
      ),
      TargetPlatform.iOS => FirebaseOptions(
        apiKey: Env.firebaseIosApiKey,
        appId: Env.firebaseIosAppId,
        messagingSenderId: Env.firebaseMessagingSenderId,
        projectId: Env.firebaseProjectId,
        storageBucket: Env.firebaseStorageBucket,
        iosBundleId: Env.firebaseIosBundleId,
      ),
      _ => throw UnsupportedError(
        'PocketPOS supports Android and iOS only ($defaultTargetPlatform).',
      ),
    };
  }
}
