# Design System

The visual reference is [`docs/image.png`](image.png). Use it for **look and feel only**: colors, spacing, typography, components and layout patterns. It does **not** define the feature set; [features.md](features.md) does that. Some mock screens use restaurant wording ("Search dishes by name…"). Use neutral retail wording in the app instead ("Search products…").

## Visual language

- **Soft, airy, calm.** Pale blue-mint gradient backgrounds, white rounded cards, one deep-teal accent.
- **Rounded everything.** Pills for chips, buttons and nav. Large radii on cards and sheets.
- **Low-contrast borders.** Thin hairline outlines in a pale teal instead of heavy shadows.
- **Generous whitespace.** Content sits on cards with 16–20 px inner padding.

## Color tokens

Define these once in `lib/core/theme/app_colors.dart`. Don't hard-code hex values in widgets.

| Token | Light | Usage |
|---|---|---|
| `primary` | `#0D5C6E` | Primary buttons, active nav pill, FAB, prices on summary rows |
| `primaryDark` | `#0A4757` | Pressed state, "Continue Billing" bar |
| `onPrimary` | `#FFFFFF` | Text and icons on primary |
| `backgroundTop` | `#DCEDF0` | Top of the screen gradient |
| `backgroundBottom` | `#F3F8F9` | Bottom of the screen gradient |
| `surface` | `#FFFFFF` | Cards, sheets, inputs |
| `surfaceTint` | `#EEF6F7` | Selected chip fill, secondary buttons ("Add Discount", "Change") |
| `outline` | `#D6E6E9` | Card and input borders, dividers |
| `textPrimary` | `#1B2B30` | Titles, item names |
| `textSecondary` | `#6B7C80` | Descriptions, dates, labels |
| `success` / `successBg` | `#2E9E6A` / `#E3F5EC` | "Paid" badge |
| `danger` / `dangerBg` | `#E0464B` / `#FDE8E8` | "Unpaid" badge, "Clear Items", delete icon |
| `categoryBadgeBg` | `#E3F1F3` | Category tag ("General") on inventory rows |

Product cards on the grid use a **very soft tint per product** (pale green, peach, pink) behind the image. The app cycles through `AppColors.productTints` keyed by product id. `ProductThumb` shows the product image (local file, else the uploaded URL) and falls back to the product's initials on that tint. The same widget previews the shop logo; `ImageField` (`lib/core/widgets/image_field.dart`) is the add / change / remove photo row used in forms.

Dark mode: keep the same structure. Swap the background to deep teal-slate (`#0F1E22` → `#14282D`), surfaces to `#1A3036`, keep `primary` a little lighter (`#2B8A9E`).

## Typography

A clean geometric sans, such as **Plus Jakarta Sans** or **Outfit**. Bundle the font files as assets for offline use (not runtime-fetched). Until the font files are added, the theme uses the platform font; all sizes and weights below already apply.

| Style | Size / weight | Example |
|---|---|---|
| `titleLarge` | 20 / 500 | Screen titles ("Confirm Sale", "Sales Report") |
| `titleMedium` | 17 / 500 | Section headers ("Sales Transactions") |
| `bodyLarge` | 15 / 500 | Item names, list titles |
| `bodyMedium` | 13 / 400 | Descriptions, form labels |
| `labelSmall` | 11 / 400 | Dates, "Vs last month", badge text |
| `amount` | 15–24 / 600 | Prices, totals, KPI values (tabular figures) |

Text size follows the user's **Text Size** setting (Small / Normal / Large) through a `textScaler`.

## Spacing and shape

- Spacing scale: `4, 8, 12, 16, 20, 24, 32`.
- Screen horizontal padding: `16`.
- Radii: inputs and small buttons `12`, cards `16`, bottom sheets `28` (top only), pills and chips `999`.
- Hairline borders `1px outline`. Shadows only on the floating bottom bar and bottom sheets (`blur 24, y 8, 6% black`).

## Core components

Build these under `lib/core/widgets/` and reuse them everywhere:

| Component | Seen in mock | Notes |
|---|---|---|
| `AppScaffold` | all screens | Gradient background, safe area, optional back button and centered title |
| `AppTopBar` | "Confirm Sale", "Transactions" | Circular white back button on the left, centered title, optional trailing action (filter icon, "Add Item" pill) |
| `SearchField` | product / transaction search | Pill-shaped white field with a leading search icon and a trailing **scan** or **mic** icon button |
| `CategoryChips` | All / Fruits / Shakes… | Horizontal scroll; selected chip filled with `surfaceTint` and primary text |
| `ProductCard` | product grid | Tinted card, name, 2-line description, price, favorite heart, product image bottom-right |
| `CartBar` | "2 Items $05.75  Next" | Sticky above the nav. Chevron expands the cart sheet |
| `CartSheet` | "2 Items  Clear Items" | Bottom sheet listing lines with a qty stepper (− n +), line total, edit and delete actions |
| `BottomNavPill` | Home / Inventory / Transaction | Floating white bar. Active item becomes a filled primary circle plus a label pill. Others are icon-only circles |
| `PeriodSelector` | "All Time  Change" | Card with a calendar icon, current period label and a "Change" pill button |
| `TransactionTile` | "Sale #1 Cash Sale $45.00 Paid" | Type label, title, date · time, amount, status badge |
| `StatusBadge` | Paid / Unpaid | Small rounded label using the success or danger tokens |
| `ActionTile` | Sale / Payment In / Purchase grid | Square outlined card with an icon in a soft circle and a label below |
| `StatCard` | Total Sales / Received | Icon, label, big value, "Vs last month" caption |
| `SettingsTile` | App Settings | Leading icon, label, trailing value plus chevron, or a switch |
| `PrimaryButton` / `SecondaryButton` | Save Item / Cancel | Full-pill, 48 px tall. Secondary is white with an outline |
| `GhostAddButton` | "+ Add Discount", "+ Add TAX" | `surfaceTint` pill with a leading plus, right-aligned |
| `LabeledField` | Quantity / Rate / Discount % | Label above a pill-shaped outlined input |

## Screen patterns from the mock

1. **Sell (Home):** top bar with menu and "Add Item". Then search, category chips, a 2-column product grid, the sticky `CartBar` and the bottom nav.
2. **Cart sheet:** dims the screen behind it. Header shows item count and "Clear Items" in danger red.
3. **Item edit sheet:** Quantity, Rate, linked Discount % and amount fields, Total Amount row, Cancel / Save. Below it: Subtotal and "Continue Billing".
4. **Confirm Sale:** invoice number and date cards, customer row ("Cash Sale" + Change), collapsible "Billing Items (n)", add discount / tax / charges, total, payment mode dropdown, notes, Cancel / Save.
5. **Inventory list:** row cards with thumbnail, name, category badge, sale price, purchase price and quantity. "Add New Item" FAB.
6. **Transactions:** search, period selector, transaction tiles. Bottom actions: "Payment In", "+", "New Sale".
7. **New transaction menu:** sheet grouped into Sales / Purchase / Other with `ActionTile`s and a close (×) button.
8. **Reports:** period selector, 2×2 `StatCard` grid, transaction list, export actions (Download, Print PDF, Excel, Share).
9. **Settings:** grouped `SettingsTile` cards with Theme, Text Size, Language, Currency and more, plus switches for Privacy Mode and App Lock.

## Motion

- Bottom sheets: spring in from the bottom, 250–300 ms.
- Nav pill: animate width and label fade between tabs (200 ms).
- Adding to cart: brief scale bump on the `CartBar` count.
- Keep animations subtle. Respect the OS "reduce motion" setting.

## Accessibility

- Minimum touch target 44×44.
- Contrast: check `textSecondary` on `surface` (aim for 4.5:1). Darken it if it fails.
- Every icon-only button needs a `Semantics` label / tooltip.
- Never show status by color alone. Badges always include text ("Paid").
