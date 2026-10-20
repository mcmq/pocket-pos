# CLAUDE.md

PocketPOS is an offline-first mobile POS and inventory app for small shops and cafés. It is built with Flutter, SQLite (Drift) and Firebase. Targets: Android and iOS, phones and tablets.

## Read before working

Read the relevant doc **before** changing related code. Keep the docs updated when behavior changes.

- [docs/features.md](docs/features.md): **what** to build. This is the source of truth for scope and priorities (P0/P1/P2).
- [docs/design-system.md](docs/design-system.md): **how it looks**. Colors, type, components, screen patterns.
- [docs/image.png](docs/image.png): visual design reference. Use it for UI/UX **only**. Never infer features from it. Its restaurant wording ("dishes") becomes neutral retail wording.
- [docs/architecture.md](docs/architecture.md): stack, folder layout, layering rules, key flows.
- [docs/data-model.md](docs/data-model.md): SQLite tables, Firestore layout, column conventions.
- [docs/offline-sync.md](docs/offline-sync.md): outbox, push/pull, conflict resolution, invoice numbering.
- [docs/setup.md](docs/setup.md): `.env` / Firebase config, emulator, codegen.

## Non-negotiables

- **Local first.** UI → controller → repository → SQLite. Only `lib/core/sync/` talks to Firestore.
- **Atomic writes.** A sale, its items, its stock movements and its outbox entries go in one DB transaction.
- **Money is `int` minor units.** Never use `double` for money.
- **Stock syncs as deltas** (`stock_movements`), never as absolute quantities.
- **IDs are client-generated UUIDs.** Synced rows are soft-deleted (`deleted_at`), never hard-deleted.
- **No secrets in source.** Firebase config comes from `.env` via `lib/core/config/env.dart`. Never commit `.env`, `google-services.json`, `GoogleService-Info.plist`, or hard-coded keys. Add any new env var to `.env.example` and `docs/setup.md` too.
- Use theme tokens and the shared widgets in `lib/core/widgets/`. Don't hard-code colors or one-off styles.

## Commands

```bash
flutter pub get
flutter run
flutter analyze
flutter test
dart run build_runner build
```

Run `flutter analyze` and `flutter test` before calling a change done.
