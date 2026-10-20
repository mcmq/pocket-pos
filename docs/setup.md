# Setup and Configuration

## Prerequisites

- Flutter (stable, Dart SDK ^3.13) — `flutter doctor` clean for Android and/or iOS
- A Firebase project (Auth, Firestore and Storage enabled)
- Optional: Firebase CLI + FlutterFire CLI for the emulator and project setup

## 1. Install dependencies

```bash
flutter pub get
```

## 2. Environment variables (`.env`)

Firebase keys are **not** committed. They are read at runtime from a `.env` file through [`flutter_dotenv`](https://pub.dev/packages/flutter_dotenv).

```bash
cp .env.example .env
```

The Firebase project is **`pocket-pos-4b0c0`**. Apps were registered with:

```bash
flutterfire configure --project=pocket-pos-4b0c0 --platforms=android,ios
```

If you re-run it, copy the values from the generated `lib/firebase_options.dart` into `.env` and then delete that file. Also remove the `com.google.gms.google-services` plugin lines it adds to `android/settings.gradle.kts` and `android/app/build.gradle.kts`: the app reads its config from `.env`, and that plugin would make builds fail on clones that lack the git-ignored `google-services.json`.

Otherwise, fill in the values from **Firebase Console → Project settings → Your apps**. Use the Android app for `ANDROID_*` and the iOS app for `IOS_*`:

| Variable | Where to find it |
|---|---|
| `FIREBASE_PROJECT_ID` | Project settings → General |
| `FIREBASE_MESSAGING_SENDER_ID` | Project settings → Cloud Messaging (project number) |
| `FIREBASE_STORAGE_BUCKET` | Storage → bucket name (e.g. `my-app.appspot.com`) |
| `FIREBASE_ANDROID_API_KEY` | `google-services.json` → `client[].api_key[].current_key` |
| `FIREBASE_ANDROID_APP_ID` | `google-services.json` → `client[].client_info.mobilesdk_app_id` |
| `FIREBASE_IOS_API_KEY` | `GoogleService-Info.plist` → `API_KEY` |
| `FIREBASE_IOS_APP_ID` | `GoogleService-Info.plist` → `GOOGLE_APP_ID` |
| `FIREBASE_IOS_BUNDLE_ID` | `GoogleService-Info.plist` → `BUNDLE_ID` |
| `USE_FIREBASE_EMULATOR` | `true` to point at local emulators (dev only) |

How it's wired:

- `.env` is listed under `flutter: assets:` in `pubspec.yaml` and ignored by git. `.env.example` is committed.
- `lib/core/config/env.dart` exposes typed getters and fails fast if a key is missing.
- `lib/core/config/firebase_options.dart` builds `FirebaseOptions` from `Env`, instead of hard-coding them as the FlutterFire-generated file does.
- `main.dart` calls `await dotenv.load()` **before** `Firebase.initializeApp(...)`.

> **Note:** Firebase client API keys are identifiers, not true secrets. They ship inside every compiled app, and `.env` is bundled as an asset. Keeping them in `.env` stops them leaking into git and makes switching dev/prod projects easy. **Real protection comes from Firestore/Storage Security Rules and Firebase App Check.** Never put server secrets (service-account keys, admin tokens) in `.env`.

Do **not** commit `google-services.json`, `GoogleService-Info.plist` or a generated `firebase_options.dart` with real values (all are in `.gitignore`).

## 3. Run

```bash
flutter run
```

## 4. Firebase emulator (optional)

```bash
firebase emulators:start --only auth,firestore,storage
```

Set `USE_FIREBASE_EMULATOR=true` in `.env`. The app then connects Auth, Firestore and Storage to `localhost` (`10.0.2.2` on the Android emulator).

## 5. Code generation

Drift uses build_runner. Generated files (`*.g.dart`) are committed, so only run this after changing tables:

```bash
dart run build_runner build
```

(Recent build_runner versions ignore `--delete-conflicting-outputs`.)

Localized strings live in `lib/core/l10n/app_en.arb`. `flutter run` / `flutter test` regenerate `AppLocalizations` automatically; to do it by hand:

```bash
flutter gen-l10n
```

## 6. Security rules

Firestore rules are in `firebase/firestore.rules` and Cloud Storage rules (product images, shop logo) in `firebase/storage.rules`. Both are referenced from `firebase.json`. Deploy them with:

```bash
firebase deploy --only firestore:rules,storage
```

Cloud Storage must be enabled for the project (Console → Storage → Get started), and `FIREBASE_STORAGE_BUCKET` must name its bucket.

## 7. Quality checks

```bash
flutter analyze
```

```bash
flutter test
```

## Platform permissions

- **Camera** (barcode scanning, product photos): `NSCameraUsageDescription` in `ios/Runner/Info.plist` (added). On Android, `mobile_scanner` declares it; `image_picker` uses the system camera app and needs no extra permission.
- **Photo library** (product photos, shop logo): `NSPhotoLibraryUsageDescription` in `ios/Runner/Info.plist` (added). On Android, `image_picker` uses the system photo picker, so no storage permission is needed.
- **Bluetooth** (thermal printers, P1): Android `BLUETOOTH_CONNECT` / `BLUETOOTH_SCAN`, iOS `NSBluetoothAlwaysUsageDescription`.
