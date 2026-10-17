# User-App UI Import — Strategy Recommendation (Synthesis)

> **Date**: 2026-10-17 · **Status**: PROPOSED — awaiting owner approval
> **Companion docs**: 01 inventory · 02 parity/gaps · 03 contract violations · 04 engineering/packaging · 05 UX/conversion

---

## Executive Verdict

The friend's repo is **not a UI drop-in and not an app**. It is a **design direction with a salvageable skin**:

- **~0% of its logic is usable.** Zero HTTP clients, zero real Firestore calls (despite cloud_firestore in pubspec), all data lives in 5 hardcoded in-memory ChangeNotifier singletons. Money math is client-side fiction (₹65/can, wallet recharges hardcoded), delivery PINs are client-minted and even printed to the rider, roles are mixed (customer app opens rider + owner screens).
- **The look is genuinely good** — Blinkit-style dense order-card grammar, gradient heroes, status pills, 4-box OTP, "DELIVERY TO" address card, big radii/typography rhythm (teal `#0D9488` vs eco-green inconsistency to reconcile).
- **Roughly 45–55% of the screen surfaces carry forward** (home shell, login visual, wallet layout, address card, order cards, quality detail presentaiton), ~⅓ is orphaned decoration or role-contamination to delete, and **everything that touches money, identity, orders, payments must be rebuilt** against `apps/user_app`'s proven controllers (138 tests, analyze-clean, backend-contract true).

**Recommendation: SKIN TRANSPLANT, not repo replacement.** Import the friend's *visual design language* into `Feature_docs/user-app-ui-design-language.md` + rebuild on a new branch replacing our user_app UI screens' look, wired to the existing controllers/ApiClient. Do not copy the friend's folder tree, data layer, or gradle.

---

## Why not the other options

| Option | Verdict | Why |
|---|---|---|
| **A. Replace `apps/user_app` with friend's repo, rewire its Firestore→API** | REJECTED | We would inherit dead deps (cloud_firestore/equatable/provider — 0 imports), 9 dead files (~1,008 lines + 353-line root demo), an un-runnable stub test, `com.example.shodasha` packaging, debug-signed releases, 4 parallel order paths, no tests. We'd be *demolishing* 138 green tests + 11 contract-true screens to rebuild them slower. |
| **B. Keep our app; restyle screens 1:1 (skin transplant)** | **RECOMMENDED** | Our feature set (register→quote→idempotent checkout→UPI poll→tracking→ledger→returns→subs) is the DIFFERENTIATOR; the friend's UI never implements any of it. Restyle = shortest diff to premium look, zero contract risk, tests keep passing. |
| **C. Rewire friend's editors into our structure** | PARTIAL | Useful only for ~8 widget-level borrowings (top_bar, order_card, mode cards, OTP row, address card) — treat as *clipboard donors*, not modules. |

---

## Proposed plan (phased, design-gated)

**Phase 0 — Design language lock (this cycle, docs only)**
- Extract tokens from friend's app into `ui-context.md` (which is currently empty template): teal/green reconciliation decision, slate neutrals, bg `#F8FAFC`, border `#E2E8F0`, radii ladder 5→16→28, eyebrow-CAPS + w900 headline type rhythm, status-pill colors.
- Build an ASCII wireframe: our 11 screens re-skinned (home=BOOK NOW machine, orders, tracking, subscriptions, profile, payments, addresses, support, login, first-run, bill) — approval gate before any code.

**Phase 1 — Branch + shell (1 branch `031-user-app-ui-revamp`)**
- Friend's repo is *reference-only* (already cloned to temp; do not vendor it in, or vendor as `design_reference/` gitignored — decide at approval).
- Port theme file first, then `user_shell.dart` nav + home screen.

**Phase 2 — Core flow reskins in dependency order** (one PR per flow, tests green each time)
1. Home (repeat-order card + mode cards look, defaults from `BookingController`)
2. Booking/checkout sheet (empties stepper, deposit line, UPI/COD chips, honest verification states)
3. Orders + tracking (dense order-card grammar, 4-step tracker pills)
4. Auth screens (login visual only — flow stays `name_number_screen` contract)
5. Profile/wallet/addresses (wallet layout transplant; address card)
6. Subscriptions (calculator kept; premium card look)

**Phase 3 — Android packaging hardening of OUR app only** (the real fix for icon/manifest: proper package name, adaptive launcher icon with brand, targetSdk current, R8 — most of this already exists in our repo, confirm + upgrade).

**Phase 4 — Verification**: 138 tests, analyze clean, device walk,deposit/e2e flows, then merge.

---

## Preconditions before any git work (owner to confirm)

1. Uncommitted work on `main` right now: `context/decision.md`, `context/progress-tracker.md` modified; 2 untracked vendor-research files (`bhopal_water_supply_vendors.md`). Commit/stash first.
2. Local branch `026-upi-monthly-redesign` is NOT merged into main — merge or delete it before creating the new branch.
3. All other 29 local branches are already merged — fine.
4. Friend's repo recommendation: reference-only clone (temp dir already exists) — NOT vendored into our repo; eliminates the `rm -rf .git` step entirely (avoids license/acidity issues and repo bloat).

## Owner decisions (LOCKED 2026-10-17)

1. **Strategy: MIX** — a few screens adopt the friend's skeleton (rewired to our controllers/data), everything else gets an in-place restyle. See plan below.
2. **Friend's repo: temp-dir reference only** (`C:\Users\Hp\AppData\Local\Temp\opencode\shodasha-friend-ui`) — not vendored, no `.git` step.
3. **Colors: teal `#0D9488` brand + green `#16A34A` reserved for money-CTAs** (BOOK NOW / Pay buttons). Structure/nav/accents = teal family.
4. **Copy: import friend's English strings as-is** for now; Hinglish content pass is a later phase.

## Revised plan (Option B-Mix)

**A. Adopt-friend-skeleton + rewire (replacement path):**

| Our screen | Friend donor | Rewire to |
|---|---|---|
| `home_screen.dart` | `customer_home_screen.dart` + top_bar + mode_selection_cards | `BookingController` defaults, catalog 2 SKU strip (₹28 refill / ₹30 jar+can), BOOK NOW |
| `name_number_screen.dart` visual skin | `login_screen.dart` (premium hero + 4-box aesthetic) | Register contract: naam + 10-digit number + @gmail.com email + demo + guest |
| `profile_screen.dart` wallet card | `wallet_screen.dart` layout | our `/ledger/me` held/dues/deposit data |
| `address_screen.dart` address card | DELIVERY TO card (in top_bar / saved_addresses extract) | our AddressController + OSM map_picker + snapshot rules |

**B. Restyle-ours (keep our logic, borrow friend's visual grammar):**
booking/checkout sheet (empties stepper + ₹150 deposit line + UPI/COD chips + honest verification states), orders + tracking (dense order-card grammar + status pills), subscription calculator card, payment history, support, bill screen.

**C. Kill list:** rider dashboard/delivery screens, owner control center, notifications screen, plant hub telemetry, live purity card (or rebuild as an honest static trust card — decide at design gate), featured-products fake trends, hardcoded wallet recharge history.

**D. Packaging (our app):** brand adaptive launcher icon, confirm package/label/targetSdk — separate small phase.

**Phases:** P0 swap-in theme (double palette resolved) → P1 branch `031-user-app-ui-revamp` → P2a iterative adopt-skeleton rewrites, P2b restyle pass, tests green every merge → P3 packaging → P4 138-test + analyze + device walk → merge.

## Remaining pre-implementation questions

- Local branch `026-upi-monthly-redesign` is unmerged — merge it into main or delete it first?
- Uncommitted `context/*.md` edits + 2 untracked vendor files on main — commit as docs commit first?
- Lead screen order for P2a: Home first, then login? (proposed)
