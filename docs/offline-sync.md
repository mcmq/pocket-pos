# Offline-first and Synchronization

## Principles

1. **Local first.** Every read and write hits SQLite. The network is never on the critical path of a sale.
2. **Outbox pattern.** Each local mutation enqueues an `outbox` entry in the **same DB transaction**. If the app crashes, nothing is lost or half-written.
3. **Idempotent pushes.** Rows have client-generated UUIDs, so a retried upload just overwrites the same Firestore document.
4. **Eventual consistency.** Devices converge once they have all pushed and pulled.

## Sync engine (`lib/core/sync/`)

```
          ┌────────────── local writes ──────────────┐
          ▼                                          │
   ┌─────────────┐   push (batched)   ┌───────────┐  │
   │   outbox    │ ─────────────────▶ │ Firestore │  │
   └─────────────┘                    └───────────┘  │
          ▲                                 │ pull (updatedAt > cursor)
          │                                 ▼        │
   ┌─────────────────────────────────────────────┐   │
   │        SQLite (Drift) — source of truth     │ ◀─┘
   └─────────────────────────────────────────────┘
```

### Triggers
- Connectivity changes to online (`connectivity_plus`, then a lightweight reachability check).
- App resumes from the foreground.
- A new outbox entry is created while online (debounced ~2 s).
- Every 15 minutes while the app is open. A true background task (`workmanager` / BGTaskScheduler) is not built yet.
- Manual "Sync now" in settings or the status indicator.

### Push
1. Read up to N (≈ 400) outbox rows in FIFO order.
2. Write them in a Firestore `WriteBatch` (max 500 ops) with `set(merge: true)`, `clientUpdatedAt` = the local `updated_at`, and `updatedAt: FieldValue.serverTimestamp()`.
3. On success, delete those outbox rows and mark the source rows `sync_status = synced` (unless they changed again and have a newer outbox entry).
4. On failure, increment `attempts` and store `last_error`, then retry with exponential backoff (2 s → 5 min cap). After 10 attempts, mark the row `error` and surface it in the UI.

### Pull
- Keep a per-collection cursor (`last_pulled_at`) in `settings`.
- Query `where updatedAt > cursor orderBy updatedAt limit 500` and page with `startAfterDocument` until a short page.
- Upsert each document locally when its `clientUpdatedAt` is newer than the local `updated_at`. A newer remote row also drops any older queued local change for that row (see conflicts).
- Transactions arrive with their items embedded; local items are replaced. Pulled stock movements trigger a recompute of `products.stock_qty`.
- Optionally attach Firestore snapshot listeners while the app is in the foreground and online, for near-real-time multi-device updates.

Firestore's own offline persistence is **disabled** (`persistenceEnabled: false`). SQLite is our cache, and two caches would conflict.

### Code map
- `lib/core/sync/sync_engine.dart`: triggers, push, pull, conflict handling, status stream.
- `lib/core/sync/remote_store.dart`: `RemoteStore` interface + `FirestoreRemoteStore`. The engine only sees this interface, so tests run against an in-memory fake.
- `lib/core/sync/sync_providers.dart`: wires connectivity, app resume and auth changes into the engine.

### Shop ownership
- A shop can be created offline with no owner. On the first sync after sign-in, the engine sets `owner_uid` to that account and writes `shops/{id}` plus `members/{uid}` (role `owner`).
- A shop owned by a different account is never synced from this device (sync shows an error). Joining another owner's shop needs invites (P1).
- Signing in on a fresh install looks up `shops where ownerUid == uid` and downloads that shop (`SyncEngine.adoptOwnedShop`).

## Conflict resolution

| Data | Strategy |
|---|---|
| Products, categories, parties, settings | **Last-write-wins** on `updated_at` (server timestamp breaks ties). |
| Stock quantity | **Never synced as an absolute value.** Only `stock_movements` (append-only deltas) sync. Each device recomputes `stock_qty = SUM(qty_delta)`, so two devices selling the same item offline merge correctly. |
| Transactions / payments | **Append-only.** Created once by one device. Edits after sync go through void + new, or an audited edit. Concurrent edits use LWW plus an audit log entry. |
| Deletes | Soft delete via `deleted_at`. A delete wins over an older update. |

Negative stock is allowed (a sale is never blocked by a stale count). It is flagged in the inventory list for review.

## Invoice numbers

Sequential numbers can't be globally coordinated while offline. Each device gets a short **device prefix** (assigned once on shop join, for example `A`, `B`) and keeps its own counter: `A-0001`, `A-0002`, `B-0001`. The internal `id` (UUID) remains the real key.

## Images

Product images and the shop logo are saved locally first. The picked photo (downscaled to 1024 px JPEG by `image_picker`) is copied by `ImageStore` (`lib/core/data/image_store.dart`) into `<app documents>/images/{rowId}-{ts}.jpg`. The row stores that path **relative** to the documents dir (`products.image_local_path`, `shops.logo_local_path`), since iOS moves the app container between updates. A new picture gets a new file name and sets the URL column to null.

The upload queue (`ImageUploader`, `lib/core/sync/image_uploader.dart`) runs inside each sync, **after the pull** so a failing upload never holds back data sync:

1. It picks rows that have a local file, no URL, and `sync_status = 'synced'` (the document already exists, so Storage rules can check the shop).
2. It uploads to Cloud Storage at `shops/{shopId}/images/{rowId}.jpg` through the `BlobStore` seam (`FirebaseBlobStore` in the app, an in-memory fake in tests).
3. It writes the download URL back to `image_url` / `logo_url` as a normal row update with an outbox entry, and the engine pushes it right away. If the picture changed during the upload, the URL is not written; the new picture goes in the next run.

A missing local file is skipped. A failed upload marks sync as errored and retries with the usual backoff.

Local paths are **device only**: `AppDatabase.localOnlyFields` strips them from outbox payloads. On pull the engine keeps this device's file while the remote URL matches the local one. A different URL means another device changed the picture, so the local file is dropped and the URL is shown instead.

Display order (`ProductThumb`, receipt): local file → `image_url` (cached with `cached_network_image`) → initials on the pastel tint. The PDF receipt embeds the local logo, or downloads the URL, and leaves the logo out if neither works.

Storage rules live in [`firebase/storage.rules`](../firebase/storage.rules): the shop owner or an active member can read and write images under their shop, up to 5 MB, `image/*` only.

## Auth while offline

Firebase Auth caches the session, so the app opens offline after one successful sign-in. If the token expires while offline, the app keeps working locally and pauses sync until re-authentication.

## UI states

- Status chip in the app bar or settings: ✓ Synced · ⟳ Syncing · ● n pending · ⚠ Sync error (tap for details).
- Never block the user on sync. Show it, don't gate on it.
