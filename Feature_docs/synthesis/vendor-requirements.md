# Vendor Requirements — Flutter Vendor/Delivery App + Next.js Admin Ops View (SYN-2)

- **Date**: 2026-09-29
- **Role**: SYN-2 Synthesizer, Shodasha Mineral Waters
- **Inputs**: `Feature_docs/research/B-operations/` (B1, B2, B3, B4, _group-B-summary), `C-competitors/C2-rekart-blueprint.md`, `D-dev-guides/D2-goteso-triapp.md`, `D-dev-guides/D3-appinop-ai-iot.md`, `E-bisleri/_group-E-summary.md`, `context/project-overview.md`
- **Surfaces**: Flutter Android vendor/delivery app (driver) + Next.js super-admin web (ops view). User-app items appear only as the other end of the contract.
- **Scope locks**: 20L Refill Rs 28 / Jar+Container Rs 30 · Rs 150/jar refundable deposit · arrival window (no live dot) · UPI+COD v1 · Hindi v1
- **Status**: Proposed for Series-3 spec lock. All market numbers are source-website claims, not audited (§08).

## Requirement list (summary)

| ID | Requirement | Source | Priority | v |
|---|---|---|---|---|
| VR-01 | Atomic doorstep triple per stop | B4 §2; B2 §1; B3 §2; B1 §4; D2 §3 | Must | v1 |
| VR-02 | Offline-tolerant capture + conflict-free sync | B2 §11; B4 §2; D2 §6 + _group-D-summary §1 | Must | v1 |
| VR-03 | Per-customer jar ledger (held + deposit + dues, never-negative) | _group-B-summary §2; B1 §5; B2 §5 | Must | v1 |
| VR-04 | Rs 150-at-booking + refund-on-closure lifecycle | E R2/R3 + §4; B4 §4; D3 §4 | Must | v1 |
| VR-05 | Cap-missing +Rs 3 handover charge | E R4 | Must | v1 |
| VR-06 | Pause schedules + auto-resume + ≥24h resume cutoff | B1 §3; B2 §4; E R9/R10; D3 §5 | Must | v1 |
| VR-07 | Auto route sheets + loading sheets (take-X / expect-Y) | B3 §10; B4 §5; B1 §4; D2 §2 | Must | v1 |
| VR-08 | WhatsApp bills + own-bank UPI QR + carry-forward + reminders | B2 §2/§6; B3 §5/§6; C2 §9; D2 §1 | Must | v1 |
| VR-09 | Evening route reconciliation (day-close) | B1 §5/chain-5; B4 §9; _group-B-summary §3 | Must | v1 |
| VR-10 | Hindi v1 (UI + bills + reminders); Gujarati v2 | B2 §11; B3 §14; B1 UX (English-only (R)) | Must v1 / v2 | v1 = Hindi |
| VR-11 | Audit on money/deposit edits + role-scoped logins | B3 §8; B4 §10 | Must (admin-only edits v1, logged) | v1 |
| VR-12 | Hold-limit block (outstanding > 3 → pause / ask deposit) + hold-days alert | B2 §5; B3 §13; C2 §8 | Must | v1 |
| VR-13 | Breakage / damage / write-off adjustments | B4 §8 | v2 (manual admin adjust in v1) | v2 |
| VR-14 | GPS pin + sequenced stops + internal nav (no customer live-dot) | B3 §4; D2 §3; scope window-no-dot | Should | v1-lite |

Deferred to v2 (model leaves room, no build now): photo PoD, per-customer/corporate rate overrides + dealer tier, payroll + expenses/P&L, prepaid wallet, route-AI auto-sequencing, customer live map. (B1 §4; B2 §6/§7; B3 §11/§12; C2 §7; D3 §1–§3.)

## Detailed requirements (each: source · priority · acceptance)

### VR-01 — Atomic doorstep triple (cans given / empties back / cash+UPI per stop)
- **Source**: B4 §2 (names it); B2 §1 (1-tap + bulk); B3 §2 (1-tap 44×44px + bulk); B1 §4 (proof per stop); D2 §3 (PoD = OTP/photo + empties + cash).
- **Priority**: Must, v1.
- **Acceptance**:
  - [ ] One stop screen captures `{stop_id, fulls_given, empties_back, cash, upi, rider, timestamp}` in a single commit; stamped who/when/where (Pure Pani rule).
  - [ ] 1-tap counters with 44×44px targets (PaniHisab candour); bulk building mode on same screen.
  - [ ] Per-stop quantity-due + empties-expected shown from route sheet.
  - [ ] Idempotency key per stop — retry/double-tap never double-counts (D2 §5).

### VR-02 — Offline-tolerant capture + sync
- **Source**: B2 §11 (offline-friendly); B4 §2 (offline + sync at plant); D2 §6 / _group-D-summary §1 (offline queue → sync).
- **Priority**: Must, v1.
- **Acceptance**:
  - [ ] Stops markable with zero signal; queued on device; auto-sync on reconnect.
  - [ ] No lost entries, no double-counted jars after sync.
  - [ ] Sync conflicts resolve per-stop (idempotency key), never last-write-wins over money/jars silently. (Exact semantics were unverified per vendor — Series-3 must lock and test.)

### VR-03 — Per-customer jar ledger (held + deposit + dues, never-negative)
- **Source**: _group-B-summary §2 (model + state diagram); B1 §5 (Customer 360, daily reconcile); B2 §5 (filled/empty/with-customer).
- **Priority**: Must, v1.
- **Acceptance**:
  - [ ] Record: `held_jars, deposit_balance, dues, rate(v1=SKU), schedule + pause windows`.
  - [ ] Invariant: `held = Σfulls − Σempties − Σwritten_off`, **never negative**; negative write rejected (422/409, surfaced in Hindi).
  - [ ] Every mutation originates from one VR-01 stop event or one audited admin adjustment — never a side notebook.
  - [ ] Read-only held+deposit+dues visible to user (kills "kitna baaki hai" calls — B2 rule).
  - [ ] States: AtPlant → InTransit → WithCustomer → AtPlant (return) / WrittenOff (admin) / AtPlant (closure recovery).

### VR-04 — Rs 150-at-booking deposit + refund-on-closure
- **Source**: E R2/R3 + §4 table (Rs 150 incl. taxes, formula); B4 §4 (new-connection → refund → closed-account); D3 §4 (Rs 150 MVP).
- **Priority**: Must, v1.
- **Acceptance**:
  - [ ] Booking shows live `deposit_due = max(0, N − E) × 150` under the empty-exchange stepper with "Rs 150/jar refundable" label (E R1/R3).
  - [ ] Deposit posts to `deposit_balance` at booking/collection (UPI/COD at door — deliberate Bisleri no-COD diverge, E §3).
  - [ ] Closure flow: return jars → refund `returned × 150` → ledger zeroed; Phase-1 via UPI/manual, wallet rails in v2 (E §3).
  - [ ] Non-Shodasha / no-deposit empties = no refund + reason shown at handover (E §3 eligibility adapt).

### VR-05 — Cap-missing +Rs 3 handover charge
- **Source**: E R4 (E2 instruction §4 verbatim).
- **Priority**: Must, v1.
- **Acceptance**:
  - [ ] Booking note: "empties must have caps".
  - [ ] Vendor handover counter for `caps_missing = M`; charge `M × 3` added at handover, shown on bill.

### VR-06 — Pause schedules + auto-resume + ≥24h resume cutoff
- **Source**: B1 §3 (pause/qty-change/holiday-skip); B2 §4 (1-tap pause + auto-resume date, incl. customer-side request); E R9/R10 (Hold Deliveries date-range; resume ≥24h + pick preferred date); D3 §5 (standing orders + pause).
- **Priority**: Must, v1.
- **Acceptance**:
  - [ ] Schedule types: daily / alternate-day / weekly / custom (weekday + Every-N-days + Odd/Even per B3 engine — ship the engine, PaniHisab §3).
  - [ ] One-tap pause with date-range hold + auto-resume date; weekend/holiday skips coexist with one-time orders on one screen.
  - [ ] Resume enforced **≥24h before** delivery day + must pick preferred delivery date (E R10).
  - [ ] Series-3 must lock skip-one vs pause-all semantics (D2 §7 open question).

### VR-07 — Auto route sheets + loading sheets
- **Source**: B3 §10 (per-driver auto: 140 fulls + 135 expected empties sample); B4 §5 (auto-built mornings); B1 §4 (auto beats + resequence); D2 §2 (assign + sequence).
- **Priority**: Must, v1 (admin-built; resequencing admin-side v1).
- **Acceptance**:
  - [ ] Admin auto-generates per-driver sheets from schedules each morning (multi-shift cutoffs per B2 §1).
  - [ ] Each sheet shows loading numbers: take-X fulls, expect-Y empties (+ stands where relevant) — kills morning miscounts.
  - [ ] Assignment pushes to driver login; pending-vs-completed tracking; WhatsApp order alerts to clients (B3 §9).

### VR-08 — WhatsApp bills + own-bank UPI QR + carry-forward dues + reminders
- **Source**: B2 §2/§6 (logo GST bills on WhatsApp, zero-custody UPI); B3 §5/§6 (worked formula, scannable bank-UPI QR, zero fee); C2 §9 (low-balance alerts + payment links); D2 §1 (invoice payment links via SMS/WhatsApp).
- **Priority**: Must, v1.
- **Acceptance**:
  - [ ] Formula: `bill = Σ(jars × rate) + previous_balance + deposit_due − payments_received`; partial payments carried, never zeroed silently. Anchor: 25×₹30 + ₹240 = ₹990 (B3 §5).
  - [ ] Bill pushed on WhatsApp showing transparent arithmetic (jars, rate math, previous, deposit, total) + scannable **supplier's own-bank** UPI QR; 100% settles to agency bank (zero-fee pattern).
  - [ ] Payment (UPI/COD at door or QR) → auto-reconcile + receipt; dues carry forward automatically.
  - [ ] Friendly Hindi payment reminders + low-balance nudges to laggards.

### VR-09 — Evening route reconciliation (day-close, never month-end surprise)
- **Source**: B1 chain-5 + §5 (ledgers reconcile daily; evening insights); B4 §9 (evening route-wise collection/pending/dues); _group-B-summary §3 (collection rule).
- **Priority**: Must, v1.
- **Acceptance**:
  - [ ] Every doorstep payment posts to the customer ledger **as taken** (or on sync).
  - [ ] Owner evening view per route: cash + UPI collected vs pending vs jars still out; revenue vs collection vs pending sample (B3 §7: 45.2k/38k/7.2k pattern).
  - [ ] Day-close discipline: retention/route-cost/jar-recovery visible by evening (Rekart rule).

### VR-10 — Hindi v1; Gujarati v2
- **Source**: B2 §11 (8 langs, Hindi-first, 30-min Hindi training); B3 §14 (10 langs, Hindi/Gujarati-first); B1 UX (English-only (R) — unverified rival claim).
- **Priority**: Must v1 = Hindi; Gujarati + rest v2.
- **Acceptance**:
  - [ ] Vendor app, bills, reminders fully usable in Hindi; driver-learnable in ~30 min (B2 bar).
  - [ ] Support path Hindi/English; bills shareable in Hindi (U-B3-01 pattern).
  - [ ] Gujarati + per-customer language preference = v2.

### VR-11 — Audit on money/deposit edits + role-scoped logins
- **Source**: B3 §8 (granular toggles + full action audit); B4 §10 (role logins + audit on collection/deposit edits, exportable).
- **Priority**: Must v1 (v1 = single vendor login + admin-only edits, all logged).
- **Acceptance**:
  - [ ] Driver view permission-scoped (Daily Entry; no customer-create / billing in v1 unless toggled).
  - [ ] Every money/deposit/ledger edit logs who/what/when (+ before-after); discard/restore audited; data exportable (Excel/PDF) any time.
  - [ ] v2: separate delivery-boy + manager logins, advances/expenses, payroll auto-calc (B2 §7).

### VR-12 — Hold-limit block + hold-days alert
- **Source**: B2 §5 (hold-limit blocking); B3 §13 (dedicated deposit field + 5+ jars / 3+ days alert); C2 §8 (auto-flag above threshold, say 3; pause rule at 2–3 outstanding).
- **Priority**: Must, v1.
- **Acceptance**:
  - [ ] Configurable hold limit, default **outstanding > 3 → pause delivery / ask deposit** (C2 flow: `Outstanding > 3? → Pause delivery / ask deposit`).
  - [ ] Alert when customer holds 5+ jars for 3+ days (PaniHisab pattern); over-limit flag surfaces on route sheet + admin.
  - [ ] Blocked issue shows Hindi reason + deposit-pay path (never silent refusal).

### VR-13 — Breakage / damage / write-off
- **Source**: B4 §8 (only Group B source with this flow); B4 editions matrix (manual → full).
- **Priority**: v2 (v1 = manual admin adjustment only).
- **Acceptance (v2)**:
  - [ ] `WithCustomer → WrittenOff` transition with reason (breakage/damage/lost) + actor + timestamp; counts stay honest.
  - [ ] v1 data model already carries `written_off` in the held invariant (VR-03) so v2 is an upgrade, not a rewrite.

### VR-14 — GPS pin + sequenced stops + internal nav (no customer live-dot)
- **Source**: B3 §4 (Maps pin + 1-click driver routing); D2 §3 (GPS nav internal); scope lock arrival-window-no-dot (project-overview; D2 §1 adapt).
- **Priority**: Should, v1-lite.
- **Acceptance**:
  - [ ] Exact house pin per customer; driver gets sequenced stop list + internal navigation.
  - [ ] Customer sees 30-min arrival window + rider name/call — no live dot in v1 (D3 §3: full route-AI + traffic ETA = v2; keep stops/sequence/geofence in model now).

## v1 / v2 split (binding)

- **v1 ships**: VR-01 through VR-12 + VR-14-lite (pin + sequence, internal nav only).
- **v2 parks**: VR-13 full flow; photo PoD (B1 §4 — keep 1-tap speed first per B1 Shodasha implication); per-customer/corporate rates + society consolidated billing + dealer tier (B2 §9; B3 §12); payroll/expenses/P&L + 30+ reports (B2 §7/§10; B3 §11); prepaid wallet + B2B postpaid/credit (C2 §7; E §3); route-AI + traffic ETA + customer live map (D3 §3); Gujarati + remaining languages; multi-plant consolidation (B4 §11).

## §08 Unverified / primary-research carry (do not spec as fact)

- Deposit Rs-value handling per vendor (only Shodasha Rs 150 + PaniHisab ₹200–400 jar-value anchor are sourced).
- Rekart price / English-only / Razorpay-API (rival claims via PaniHisab compare — B1/B3 notes).
- Pure Pani traction (10k+/4.7), zero-custody settlement path, offline conflict semantics; PaniHisab tier caps, offline depth, GST-validity of bill images; EPIXS demo UX (not executed), sync semantics, any pricing.
- Per PDF §06 footer rule: vendor numbers above are source-website claims — confirm via local survey before locking Shodasha pricing/deposit constants (see `pricing-deposit-model.md` §8).
