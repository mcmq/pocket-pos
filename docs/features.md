# Features

This file is the source of truth for **what** PocketPOS does. The design mock ([image.png](image.png), [design-system.md](design-system.md)) only covers **how it looks**.

Priority legend: **P0** = MVP, **P1** = next, **P2** = later.

## 1. Sales / Checkout (P0)

- Product grid with **search** (name, SKU, barcode) and **category filter chips**.
- **Barcode scanning** with the camera. A scan adds the product to the cart, or offers "Create product" when the code is unknown.
- **Cart**: add, remove, change quantity, edit the unit price per line, discount per line (% or amount, the two fields stay linked), clear cart.
- **Checkout (Confirm Sale)**:
  - Auto-incrementing invoice number per device (see [offline-sync.md](offline-sync.md#invoice-numbers)), editable invoice date.
  - Customer: "Cash Sale" (walk-in) by default, or pick / create a **party** (customer).
  - Cart-level discount, tax (one or more rates, inclusive or exclusive), additional charges (delivery, packaging).
  - Payment mode: Cash, Card, Mobile Money, Bank Transfer, Credit (unpaid). Split payments are P1.
  - Amount received, change due, status **Paid / Partially Paid / Unpaid**.
  - Notes / remarks.
- Stock is decremented **in the same local database transaction** that saves the sale.
- Parked / held carts (P1).

## 2. Digital Receipts (P0)

- Receipt view after each sale: shop header (name, logo, address, phone, tax ID), lines, totals, payment, footer note.
- Share as **PDF** or **image** through the system share sheet (WhatsApp, SMS, email).
- Print to Bluetooth thermal printers, 58 / 80 mm (P1).
- Reprint or reshare from transaction history.

## 3. Inventory (P0)

- Product CRUD: name, description, image, category, SKU, barcode, unit (pcs, box, kg…), sale price, purchase price, tax rate, current stock, low-stock threshold, active flag.
- Categories CRUD (drive the chips on the sell screen).
- **Automatic stock updates** from sales, sale returns, purchases and purchase returns.
- Manual **stock adjustment** with a reason (damage, count correction, opening stock). Every change writes a `stock_movements` row, so stock is auditable.
- Low-stock indicator and filter. Low-stock notification (P1).
- Inventory valuation (stock × purchase price) in reports.
- Import / export products via CSV (P2).

## 4. Transactions (P0)

The "+" menu groups transaction types:

| Group | Types | Stock effect | Cash effect |
|---|---|---|---|
| Sales | Sale (P0), Payment In (P0), Sale Return (P1), Quotation (P1) | − on sale, + on return, none for quotation | + / − |
| Purchase | Purchase (P1), Payment Out (P1), Debit Note / Purchase Return (P2) | + / − | − / + |
| Other | Expenses (P1), Party-to-Party Transfer (P2) | none | − |

- Transaction list with search, **period filter** (Today, Yesterday, This Week, This Month, Custom, All Time) and type / status filters.
- Transaction detail with edit (rules below), void, and reshare receipt.
- Editing a synced sale creates an audit entry. Voiding reverses its stock movements. Hard delete is never allowed.
- A quotation can be converted into a sale (P1).

## 5. Parties (P1)

- Customers and suppliers: name, phone, email, address, opening balance.
- Running balance (receivable / payable) from sales, purchases and payments.
- Party ledger / statement shareable as PDF.

## 6. Reports (P0 basic, P1 full)

- Dashboard KPIs for the chosen period, each compared with the previous period: **Total Sales** (count), **Total Amount**, **Received Amount**, **Unpaid Amount**.
- Sales report: list plus totals. Export to **PDF**, **Excel (xlsx)**, **Share**, **Download** (P1).
- Top products, sales by category, sales by payment mode (P1).
- Stock report and low-stock report (P1).
- Profit report: sales − cost of goods sold (P2).

## 7. Offline-first and Sync (P0)

- The app is fully usable with **no internet**: every read and write goes to local SQLite first.
- Changes queue in an outbox and **sync automatically** when connectivity returns. A manual "Sync now" is also available.
- Sync status indicator (synced / pending count / error).
- Multi-device support for one shop, with conflict resolution.
- Details: [offline-sync.md](offline-sync.md).

## 8. Auth, Shop and Users (P0 basic)

- Firebase Auth sign-in (email + password; phone OTP is P1).
- On first launch, **create a shop** (name, currency, address, tax settings) or **join** one through an invite code (P1). Shop creation works offline; signing in is optional and can happen later from Settings → Account & sync. "Sign in to restore" downloads a shop the account already owns.
- Roles (P1): **Owner** (everything), **Manager** (everything except billing / users), **Cashier** (sell, view own sales, no price or stock edits).
- The app stays usable offline after the first sign-in (cached session).

## 9. Settings (P0)

- Theme: Light / Dark / System.
- Text size: Small / Normal / Large.
- Language (English first; i18n via ARB files from day one).
- Currency: code, symbol position (start / end), decimal places.
- Date and time format, number grouping (`1,000,000` vs `10,00,000`).
- Receipt header and footer, logo.
- Tax rates management.
- **Privacy Mode**: blur amounts on dashboards (P1).
- **App Lock**: PIN / biometric lock on open (P1).
- Backup: export / import the local DB file (P2). Firestore acts as the cloud backup once signed in.
- About / Privacy Policy.

## Non-functional requirements

- Checkout in **≤ 3 taps** after items are in the cart.
- Product search results in < 100 ms for 5,000 products (indexed SQLite queries).
- App cold start < 2 s on a mid-range Android device.
- No data loss: every money / stock mutation is one atomic local transaction.
- Money is stored as **integer minor units** (cents). Never use `double` for money.
- Works on phones (portrait) and tablets. Tablets get a two-pane sell screen (grid + cart side by side).
