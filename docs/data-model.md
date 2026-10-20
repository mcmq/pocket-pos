# Data Model

The same logical schema lives in **SQLite (Drift)** on the device and in **Cloud Firestore** in the cloud.

## Conventions (all synced tables)

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT (UUID v4) | Generated on the device, so offline inserts never collide |
| `shop_id` | TEXT | Tenant key. Every query is scoped by shop |
| `created_at` | INTEGER (ms epoch, UTC) | |
| `updated_at` | INTEGER (ms epoch, UTC) | Bumped on every local change, used for conflict resolution |
| `deleted_at` | INTEGER? | Soft delete. Nothing synced is ever hard-deleted |
| `version` | INTEGER | Incremented on each local change |
| `sync_status` | TEXT | `pending` / `synced` / `error` (local only, never uploaded) |
| `device_id` | TEXT | Device that last modified the row |

Money columns end in `_minor` and hold **integer minor units** (for example cents). Quantity columns (`stock_qty`, `qty`, `qty_delta`, `low_stock_threshold`) are `REAL`, because one column has to hold both counted and weighed units. The UI only accepts decimals for fractional units (kg, g, l, ml, m) and rounds `qty × price` to minor units once per line.

## Tables

### shops
`id, name, phone, address, tax_id, currency_code, currency_symbol, currency_position, decimal_places, logo_url, logo_local_path?, receipt_header, receipt_footer, owner_uid`

`logo_local_path` was added in schema version 2.

`owner_uid` is null for a shop created offline before sign-in. The first account that syncs it becomes the owner.

### users (shop members)
`id (= Firebase uid), shop_id, name, email, role (owner|manager|cashier), active`

### categories
`id, shop_id, name, sort_order, color`

### products
`id, shop_id, category_id?, name, description, sku?, barcode?, unit, image_url?, image_local_path?, sale_price_minor, purchase_price_minor, tax_rate_id?, stock_qty, low_stock_threshold, track_stock (bool), active (bool), is_favorite (bool)`

`image_local_path` and `logo_local_path` are **local only**: a path relative to the app documents dir, never uploaded (see [offline-sync.md → Images](offline-sync.md#images)). `image_url` / `logo_url` hold the Cloud Storage download URL and do sync.

Indexes: `(shop_id, name)`, `(shop_id, barcode)`, `(shop_id, sku)`. Barcode uniqueness is enforced by `CatalogRepository.saveProduct`, not by a unique index: two offline devices could create the same barcode, and a unique index would make the pull fail.

### parties
`id, shop_id, type (customer|supplier|both), name, phone, email, address, opening_balance_minor`

### tax_rates
`id, shop_id, name, rate_bps (basis points, 1500 = 15%), inclusive (bool)`

### transactions
One table for every document type, so lists and reports query a single place.

`id, shop_id, type (sale|sale_return|quotation|payment_in|purchase|purchase_return|payment_out|expense|transfer), number (display string, e.g. "A-0012"), device_seq, date, party_id?, subtotal_minor, discount_minor, tax_minor, charges_minor, total_minor, paid_minor, status (paid|partial|unpaid|void), payment_mode (cash|card|mobile_money|bank|credit), notes, breakdown_json, ref_transaction_id? (e.g. return → original sale, payment-in → the sale it pays), created_by`

`breakdown_json` snapshots the applied taxes and charges for receipts: `{"taxes": [{name, rateBps, inclusive, amountMinor}], "charges": [{label, amountMinor}]}`. `tax_minor` includes inclusive tax (already inside the prices) and exclusive tax (added on top).

Payment In uses its own per-device series: `A-P0001`.

### transaction_items
`id, transaction_id, product_id?, name_snapshot, unit_snapshot, qty, unit_price_minor, discount_minor, tax_minor, line_total_minor, cost_price_minor (snapshot for profit reports)`

Snapshots keep historic receipts correct after a product is renamed or repriced.

### payments
`id, shop_id, transaction_id?, party_id?, direction (in|out), amount_minor, mode (cash|card|mobile_money|bank|other), reference, date`

### stock_movements
`id, shop_id, product_id, qty_delta, reason (sale|sale_return|purchase|purchase_return|adjustment|opening|void), transaction_id?, note`

Voiding a sale appends `void` movements that reverse its `sale` movements; nothing is deleted.

`products.stock_qty` is a cached value. It must always equal `SUM(qty_delta)` for that product. A periodic integrity check can rebuild it.

### outbox (local only)
`id (autoincrement), table_name, row_id, op (upsert|delete), payload_json, created_at, attempts, last_error`

### settings (local only)
Key/value for device preferences: `shop_id`, `device_id`, `theme`, `text_size`, `language`, `date_format`, `time_format`, `number_grouping`, `invoice_prefix`, `invoice_seq`, `payment_in_seq`, `last_sync_at`, and `cursor_<collection>` pull cursors.

## Firestore layout

```
shops/{shopId}
shops/{shopId}/members/{uid}
shops/{shopId}/categories/{id}
shops/{shopId}/products/{id}
shops/{shopId}/parties/{id}
shops/{shopId}/taxRates/{id}
shops/{shopId}/transactions/{id}          # items embedded as an array (bounded size)
shops/{shopId}/payments/{id}
shops/{shopId}/stockMovements/{id}
```

Cloud Storage holds product images and the shop logo at `shops/{shopId}/images/{rowId}.jpg` (the row id is the product id, or the shop id for the logo).

Every document carries `updatedAt` (server timestamp on write, used as the pull cursor), `clientUpdatedAt` (the local `updated_at`, used for last-write-wins) and `deletedAt`. Documents mirror the local JSON field names (camelCase). `products` documents never contain `stockQty`, and no document contains `syncStatus`, `imageLocalPath` or `logoLocalPath`.

**Security rules (outline):** a user can read and write `shops/{shopId}/**` only if `members/{request.auth.uid}` exists and is active. Role checks restrict cashiers (no product price edits, no deletes). The rules live in [`firebase/firestore.rules`](../firebase/firestore.rules) (wired in `firebase.json`). Test them with the emulator.
