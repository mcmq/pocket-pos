import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Typed access to values loaded from `.env` (see docs/setup.md).
///
/// Call `await Env.load()` before reading any getter.
abstract final class Env {
  static Future<void> load() => dotenv.load(fileName: '.env');

  static String get firebaseProjectId => _required('FIREBASE_PROJECT_ID');
  static String get firebaseMessagingSenderId =>
      _required('FIREBASE_MESSAGING_SENDER_ID');
  static String get firebaseStorageBucket =>
      _required('FIREBASE_STORAGE_BUCKET');

  static String get firebaseAndroidApiKey =>
      _required('FIREBASE_ANDROID_API_KEY');
  static String get firebaseAndroidAppId => _required('FIREBASE_ANDROID_APP_ID');

  static String get firebaseIosApiKey => _required('FIREBASE_IOS_API_KEY');
  static String get firebaseIosAppId => _required('FIREBASE_IOS_APP_ID');
  static String get firebaseIosBundleId => _required('FIREBASE_IOS_BUNDLE_ID');

  static bool get useFirebaseEmulator =>
      dotenv.maybeGet('USE_FIREBASE_EMULATOR')?.toLowerCase() == 'true';

  /// True when the shared Firebase keys are present, so Firebase can start.
  static bool get isFirebaseConfigured =>
      _has('FIREBASE_PROJECT_ID') &&
      _has('FIREBASE_MESSAGING_SENDER_ID');

  static bool _has(String key) => (dotenv.maybeGet(key) ?? '').isNotEmpty;

  static String _required(String key) {
    final value = dotenv.maybeGet(key);
    if (value == null || value.isEmpty) {
      throw StateError('Missing "$key" in .env — see docs/setup.md');
    }
    return value;
  }
}
