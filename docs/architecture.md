# Architecture

## Stack

| Concern | Choice |
|---|---|
| UI | Flutter (Material 3, custom theme. See [design-system.md](design-system.md)) |
| State management | Riverpod (`flutter_riverpod` + `riverpod_annotation`) |
| Navigation | `go_router` with a `StatefulShellRoute` for the bottom nav tabs |
| Local DB | SQLite via **Drift** (type-safe queries, migrations, reactive streams) |
| Cloud | Firebase: Auth, Cloud Firestore, Cloud Storage (product images), Crashlytics |
| Config / secrets | `flutter_dotenv`, loaded from `.env` (see [setup.md](setup.md)) |
| Connectivity | `connectivity_plus` plus a real reachability check before syncing |
| Background sync | Foreground triggers today (connectivity, resume, new changes, 15-min timer). `workmanager` / BGTaskScheduler is a follow-up |
| Barcode | `mobile_scanner` |
| Receipts / export | `pdf` + `printing`, `excel`, `share_plus` |
| Models | Drift-generated data classes (`Product`, `Txn`, …) double as entities. `freezed` only if a need appears |
| IDs | UUID v4 (`uuid`), generated on the device |

## Layering

Feature-first folders, each with clean layers inside:

```
lib/
├── main.dart                 # loads .env, inits Firebase, runs ProviderScope(App)
├── app.dart                  # MaterialApp.router, theme, localization
├── core/
│   ├── auth/                 # AuthService (Firebase Auth wrapper)
│   ├── config/               # env.dart, firebase_options.dart
│   ├── data/                 # repositories shared by several features (catalog, sales, parties, shop)
│   ├── database/             # Drift database, tables, migrations
│   ├── l10n/                 # ARB files + generated AppLocalizations
│   ├── providers/            # app-wide Riverpod providers (db, settings, session, formats)
│   ├── router/               # go_router config
│   ├── sync/                 # outbox push/pull engine, RemoteStore (Firestore adapter), image upload queue (BlobStore → Storage)
│   ├── theme/                # app_colors.dart, app_theme.dart, text styles
│   ├── widgets/              # shared components (see design-system.md)
│   └── utils/                # money, pricing / tax math, periods, quantities
└── features/
    ├── auth/
    ├── sell/                 # product grid, cart, checkout, receipt
    ├── inventory/
    ├── transactions/
    ├── parties/
    ├── reports/
    └── settings/
        ├── data/             # feature-only data code (e.g. receipt / report PDF builders)
        └── presentation/     # screens, widgets, Riverpod controllers
```

### Rules

1. **UI never talks to Firebase directly.** Screens → controllers → repositories → **local DB**. Only the sync engine talks to Firestore.
2. **The local DB is the source of truth for the UI.** Screens watch Drift streams, so remote changes pulled by sync appear automatically.
3. **Writes are local and atomic.** Each use case (for example `CompleteSale`) runs in one Drift transaction. It writes the domain rows, the stock movements, and the outbox entries together.
4. **Money is `int` minor units** behind a `Money` value type. Format only at the edge.
5. Features may depend on `core/` but not on each other's `data/` or `presentation/`. Shared domain types and repositories used by more than one feature go in `core/` (`core/data/`). Features reach each other's screens only through routes.
6. Repositories are concrete classes over Drift; tests use a real in-memory database instead of mocks. The seams to the cloud are `RemoteStore` (Firestore) and `BlobStore` (Cloud Storage) in `core/sync/`.

## Key flows

### Complete a sale

```
CheckoutScreen ──▶ SalesRepository.completeSale(SaleDraft)
                          └─ db.transaction {
                               insert transactions row (type=sale)
                               insert transaction_items rows
                               insert stock_movements rows (−qty) & update products.stock
                               insert payments row (if paid)
                               insert outbox entries for each changed row
                             }
                  ──▶ navigate to ReceiptScreen
SyncEngine (listens to outbox + connectivity) ──▶ pushes to Firestore when online
```

### App start

1. `WidgetsFlutterBinding.ensureInitialized()`
2. `await dotenv.load()` → `Firebase.initializeApp(...)` if `.env` has keys (otherwise the app runs local-only).
3. Open the Drift DB and load the `settings` table (theme etc. are ready for the first frame).
4. Restore the auth session (Firebase caches it, works offline).
5. Start the `SyncEngine` (no-op until signed in and online).
6. The router sends the user to `/setup` until a shop exists, then to `/sell`.

## Testing

- **Unit:** repositories and money / tax math, with an in-memory Drift DB (`NativeDatabase.memory()`).
- **Sync:** an in-memory `FakeRemoteStore` (see `test/core/sync_engine_test.dart`) with two simulated devices, to test outbox draining, delta stock merging and conflicts. (`fake_cloud_firestore` does not support `cloud_firestore` 7 yet.)
- **Widget:** the full offline sale flow (`test/features/sale_flow_test.dart`). Drift does real async I/O, so widget tests alternate `tester.runAsync` with `pump` instead of `pumpAndSettle`.
- **Integration:** `integration_test` for a full offline sale → reconnect → synced flow.
