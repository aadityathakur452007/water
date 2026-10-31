# Handoff Prompt — Next Agent Session: Parallel Unslop Audit (Donor app first, Vendor app second)

> Copy everything below this line into a NEW agent session.
> This session produces **documents, not code**. One branch, ~20 parallel agents, one markdown
> file per screen cluster, then a synthesis and an approval gate. Implementation starts only
> after the owner approves.

---

## MISSION

Find everything wrong with the **Donor customer app** (`apps/user_app_donor`) and the
**Vendor app** (`apps/vendor_app`) — every interaction, every flow, every spacing value,
every component, every dead function — and write it down as evidence-backed markdown so the
owner can approve a fix plan.

The donor app is the main target. The vendor app is second. Nothing else is in scope.

Done means: `Feature_docs/ux-unslop-audit/` contains one audit file per screen cluster, an
index, a deduplicated ranked backlog, and a list of owner decisions — all committed on a new
branch — and **zero application code changed**.

---

## THE FOUR LAWS OF THIS SESSION

1. **No app code.** This is an audit. The only files you may create or edit are markdown under
   `Feature_docs/ux-unslop-audit/`. Do not touch `lib/`, `test/`, `workers/`, `pubspec.yaml`,
   CI, or config. (A throwaway, gitignored screenshot harness is the single exception — see
   Phase 0.)
2. **No claim without evidence.** Every finding cites `path:line`, a command output, or a
   screenshot you actually opened. No evidence → write `UNVERIFIED:` and the command that
   would prove it.
3. **No nostalgia.** The current build is a first draft, not a benchmark. "It already passed
   review", "it was designed by a designer", "it shipped" are not arguments. A screen earns
   its place by passing this audit.
4. **No design hallucination.** Do not imagine a redesign from memory or from a template. The
   direction must come from the product (water delivery, 20 L jars, Bhopal, trust, doorstep
   service) and from what the code actually renders.

---

## STEP 0 — READ FIRST (in this order, before anything else)

From repo root `C:\Users\Hp\Water`:

1. `Agent.md` — execution protocol (design-first, approval is a hard gate).
2. `SKILLS.md` — skill index.
3. `context/project-overview.md`, `context/architecture.md`, `context/ui-context.md`,
   `context/code-standards.md`, `States.md`.
4. `context/progress-tracker.md` — only the "Current Phase" section and the last 3 entries.
   `context/flow.md` and `context/decision.md` — **grep, do not read whole** (they are 150–470 KB).
5. **Load the `unslop` skill and read `~/.config/opencode/skills/unslop/SKILL.md` end to end.**
   Also read its `references/signs.md`, `references/tokens.md`, `references/effects.md`,
   `references/visuals.md`. You will apply it to every screen, not summarize it.
6. `DESIGN-PSYCHOLOGY.md` — skim the principles list only.
7. `Feature_docs/user-app-ui-import-audit/05-uiux-conversion-review.md` — prior UX review;
   treat it as *history*, not as truth. Anything it claims must be re-verified in code.

Load and name these skills in your first response: **`unslop`** (primary), plus
**`design-taste-frontend`**, **`mobile-native`**, **`ui-checklist`**, **`redesign`**.
State one rule from `unslop` you will enforce: *richness goes into one or two content moments,
the chrome stays quiet.*

---

## STEP 1 — BRANCH (do this before spawning anything)

```bash
git status                      # if dirty: STOP and ask the owner to commit/stash first
git branch --show-current       # expected: 036-demo-cleanup-admin-code
git switch -c 037-uiux-unslop-audit
```

- Never branch with uncommitted app changes silently carried over. The working tree currently
  has modified auth files on `036-*`; ask the owner before proceeding if they are still dirty.
- Commit only the audit docs on this branch. Conventional commits, e.g.
  `docs(ux-audit): add 20-screen unslop audit and ranked backlog`.
- Do not push. Do not open a PR. The owner approves first.

---

## STEP 2 — PHASE 0: SHARED EVIDENCE (do this yourself, before parallel agents)

Every agent needs the same ground truth. Produce it once:

1. **Baseline gates** (record the output, do not fix anything):
   ```bash
   cd apps/user_app_donor && flutter analyze && flutter test
   cd ../vendor_app       && flutter analyze && flutter test
   ```
2. **Token extraction.** From `lib/core/theme.dart` (donor) and `lib/core/theme.dart` (vendor),
   list every token actually defined: colors, type scale, radii, spacing, motion durations.
   Write it to `Feature_docs/ux-unslop-audit/00-tokens-actual.md`. This is the ruler every
   agent measures against — not `ui-context.md`, which is the *intended* contract.
3. **Drift check.** Compare `context/ui-context.md` against the real theme file. Any token in
   the doc that does not exist in code (or vice versa) is drift — log it.
4. **Visual evidence (best effort, timeboxed to 30 minutes total).**
   - Preferred: `cd apps/user_app_donor && flutter run -d chrome --web-port 5599`, then capture
     with the unslop skill's `scripts/snapshot.mjs` (Playwright). Login is reachable without a
     session; authenticated screens will show their real empty/error states, which is still
     evidence.
   - Fallback for authenticated screens: a **throwaway** golden harness
     (`test/audit_screens_test.dart`, `flutter test --update-goldens`) that pumps screens with
     fake data reused from the existing tests (`donor_shell_test.dart`,
     `login_screen_test.dart`, `subscription_billing_test.dart`, `state_fixes_test.dart`).
     Output PNGs to `Feature_docs/ux-unslop-audit/shots/`. Do **not** commit the harness.
   - If neither works, every agent writes `VISUAL: not captured — <reason>` and audits from
     code. Never describe a screenshot you did not open.
5. **Inventory of "slop signals"** — run these and paste the counts into
   `00-slop-signals.md` (per app, per feature folder):
   ```bash
   rg -n "LinearGradient|RadialGradient|SweepGradient|BackdropFilter|ImageFilter" lib
   rg -n "BoxShadow\(" lib
   rg -n "Color\(0x|Colors\.(purple|indigo|violet|blue|green|amber)|withOpacity|withValues" lib
   rg -n "EdgeInsets\.(all|symmetric|only|fromLTRB)\(" lib
   rg -n "SizedBox\((height|width):" lib
   rg -n "fontSize:" lib
   rg -n "onPressed: \(\) \{\}|onTap: \(\) \{\}|TODO|FIXME|// ignore" lib
   ```
   Counts are not findings by themselves; they are the map of where to look.

Write `00-index.md` with: branch, commit, gate results, evidence status (which screens have
screenshots), and the agent roster checklist (unchecked until each file lands).

---

## STEP 3 — PHASE 1: PARALLEL AGENTS (this is the core of the session)

Spawn **read-only subagents in parallel, max 5 concurrent**, in the order listed. Each agent:

- owns **exactly one screen cluster** and writes **exactly one markdown file**;
- never edits another agent's file, never edits app code, never commits;
- gets the shared context listed below and nothing else (protect its context window);
- is told which files to read and which commands to run;
- has a 90-minute budget. If blocked, it writes what it has, marks `BLOCKED: <reason>`, and stops.

**Shared context block to paste into every subagent prompt:**

```
Repo: C:\Users\Hp\Water. Branch: 037-uiux-unslop-audit. Read-only audit, no code changes.
Read first: ~/.config/opencode/skills/unslop/SKILL.md (+ references/signs.md, tokens.md),
context/ui-context.md, States.md, Feature_docs/ux-unslop-audit/00-tokens-actual.md,
00-slop-signals.md.
Read only the files listed in your assignment plus lib/core/theme.dart and
lib/shared/ui/*. Do not read context/decision.md or context/flow.md in full — grep them.
Every claim needs path:line or a screenshot you opened. If you cannot verify it, write
UNVERIFIED: <command that would verify>. Do not propose new dependencies. Do not propose
changes to money math, auth, API contracts, or test expectations — flag them instead.
Write your file to Feature_docs/ux-unslop-audit/<your-file>.md using the 18-section
contract below. Nothing else.
```

### Donor app — 12 agents (primary target, do these first)

| # | File to write | Scope (read these) | Why it matters |
|---|---|---|---|
| D1 | `01-donor-auth.md` | `features/auth/login_screen.dart` (691), `auth_gate.dart`, `auth_controller.dart` (672), `features/addresses/first_run_sheet.dart` | First impression + trust; 672-line controller is a state-machine risk |
| D2 | `02-donor-shell-nav.md` | `features/shell/donor_shell.dart` (667), `features/home/notifications_screen.dart` (297) | 5-tab shell, back stack, notification entry |
| D3 | `03-donor-home.md` | `features/home/customer_home_screen.dart` (306) + `widgets/top_bar.dart` (269), `mode_selection_cards.dart`, `live_purity_card.dart`, `featured_products.dart` | The screen that must carry the product's character |
| D4 | `04-donor-booking.md` | `features/booking/booking_sheet.dart` (**1716**), `stepper.dart`, `product_detail_sheet.dart`, `quote_confirm.dart`, `booking_controller.dart` (499), `product_catalog.dart` | Largest file in the app; the money path |
| D5 | `05-donor-orders.md` | `features/orders/my_orders_screen.dart`, `order_card.dart` (267), `orders_controller.dart` (1171, list/filter parts only) | Dense repeated card grammar |
| D6 | `06-donor-tracking.md` | `features/orders/tracking_screen.dart` (**1613**) | Live state, polling, OTP, the most complex screen |
| D7 | `07-donor-bill-rating.md` | `features/orders/bill_screen.dart`, `rating_sheet.dart` | End-of-flow trust moment |
| D8 | `08-donor-subscriptions.md` | `features/subscriptions/subscription_screen.dart` (**1558**), `plan_builder_sheet.dart` (839), `subscription_controller.dart` (607) | Billing modes are explained poorly or well; nothing in between |
| D9 | `09-donor-wallet.md` | `features/wallet/donor_wallet_screen.dart` (638), `payment_history_screen.dart` (471), `wallet_controller.dart` | Money truth; fake-zero risk |
| D10 | `10-donor-addresses.md` | `features/addresses/address_screen.dart` (**1456**), `map_picker.dart` (410), `selected_address_store.dart` | 1456 lines for CRUD = composition problem |
| D11 | `11-donor-profile.md` | `features/profile/donor_profile_screen.dart` (550), `edit_profile_sheet.dart`, `profile_controller.dart` | Settings junk drawer risk |
| D12 | `12-donor-support-returns.md` | `features/support/support_screen.dart` (**1069**), `support_controller.dart`, `features/returns/return_sheet.dart` (437), `returns_controller.dart` | Support is where trust is lost; 1069 lines is suspicious |

### Vendor app — 4 agents (secondary target)

| # | File to write | Scope |
|---|---|---|
| V1 | `13-vendor-auth-shell-profile.md` | `features/auth/vendor_code_screen.dart`, `auth_gate.dart`, `vendor_strings.dart`, `features/shell/vendor_shell.dart`, `features/profile/profile_screen.dart` (450) |
| V2 | `14-vendor-route-stops.md` | `features/route/route_screen.dart` (673), `route_controller.dart`, `features/stops/stop_detail_screen.dart` (606), `pod_sheet.dart`, `triple_sheet.dart`, `stops_controller.dart` |
| V3 | `15-vendor-duty-sync.md` | `features/duty/duty_screen.dart`, `duty_controller.dart`, `features/sync/sync_screen.dart`, `sync_controller.dart`, `core/cascade.dart` |
| V4 | `16-vendor-customers-inventory-earnings-support.md` | `features/customers/*`, `features/inventory/inventory_screen.dart`, `features/earnings/*`, `features/support/*` |

### Cross-cutting — 4 agents (run after the screen agents, they need their findings)

| # | File to write | Scope |
|---|---|---|
| X1 | `17-system-tokens-shared-ui.md` | Both `lib/core/theme.dart`, both `lib/shared/ui/*` (donor: `app_button`, `app_text_field`, `app_card`, `app_sheet`, `app_banner`, `app_icon_button`, `status_pill`, `app_state_view`, `section_header`), `AppMotion`. Audit: token drift, one-off values, variants that are never used, primitives that exist but screens bypass |
| X2 | `18-duplication-dead-code.md` | Repo-wide within both apps: copy-pasted widgets/helpers/formatting/validators, 3+ collaborators on one job, cross-feature imports, `shared/ui` bypassed, controllers with unread fields, params never used, empty callbacks, fake `Future.delayed` loading, hardcoded lists/prices/names, symbols with zero callers (grep the symbol including tests before calling it dead) |
| X3 | `19-flows-state-machines-nav.md` | Cross-screen: booking → quote → checkout → payment → order → tracking → bill → rating; subscription lifecycle; returns; auth refresh/401; every route, back-stack behaviour, dead ends, double-submit, stale state. Produce mermaid `stateDiagram` per flow with **current** and **proposed** versions |
| X4 | `20-copy-a11y-motion.md` | All user-facing strings in both apps (current → problem → proposed), semantics labels, 48dp targets, contrast pairs, dynamic type, `MediaQuery.disableAnimationsOf` coverage, layout-property animations, polling that ignores app lifecycle |

If your harness has no subagents, run the same roster sequentially in the same order and keep
the same file-per-cluster contract.

---

## THE 18-SECTION CONTRACT (every audit file, in this exact order)

Numbered headings, tables over prose, no filler. A reader must be able to act on it without
opening the code.

1. **Header** — screen(s), file paths + line counts, routes/entry points, agent, date, evidence
   status (`screenshots: yes/no`).
2. **Job to be done** — one paragraph: what the user is trying to finish here, and the single
   moment that must feel good. No marketing language.
3. **What the code actually renders** — the widget tree in 10–20 lines, plus the states the
   screen can be in. Cite the file that owns each state.
4. **Interaction inventory** — table: `trigger | handler | state change | result/navigation | file:line`.
   Every tap, long-press, swipe, scroll-triggered load, pull-to-refresh, back press, keyboard
   action. Missing handlers are findings too.
5. **Flow map** — mermaid flowchart: entry points in, exits out, dead ends, loops. Mark each
   edge that is confusing or unnecessary.
6. **Slop audit** — table: `sign | where (file:line) | why it reads AI-generated | verdict`.
   Use the unslop `signs.md` list. Include spacing noise, gradient/glow, emoji, badge spam,
   uppercase tracked labels, pulsing, glossy blobs, three competing accents.
7. **Spacing & layout audit** — table: `element | current value (file:line) | token it should use | proposed`.
   Pull real numbers from `EdgeInsets`, `SizedBox`, `padding`, `gap`. Flag every value off the
   4/8/12/16/24/32 scale and every inconsistent sibling.
8. **Type & color audit** — same table shape. Flag screen-local hex, `withOpacity`, raw
   `fontSize`, weight soup, contrast failures, and any second token system.
9. **Component audit** — three lists: (a) should be a shared primitive, (b) duplicated across
   screens, (c) wrong composition — more than two things collaborating on one job, sheets that
   own business logic, widgets that re-implement `shared/ui`, state spread across 3+ owners.
   For each: the smallest structural fix, not a rewrite.
10. **Logic & flow defects** — wrong order, redundant steps, missing confirmation, missing
    undo, silent failure, optimistic UI that lies, navigation traps, double submission, stale
    reads, retry that duplicates a write, keyboard covering the CTA, back that loses input.
11. **Dead / for-show code** — table: `symbol | file:line | callers found | verdict
    (dead | for-show | test-only | keep)`. Include unused params, unread controller fields,
    `onPressed: () {}`, fake delays, hardcoded demo data, comments that describe removed code.
12. **Copy audit** — table: `current string | file:line | problem | proposed`. Cover titles,
    buttons, empty states, errors, confirmations. Ban raw status codes, internal jargon, and
    shouting.
13. **States matrix** — rows: loading, empty, error (network), error (server), stale, offline,
    401/403, validation, submitting, success. Columns: `present? | where | honest? | gap`.
    Missing states are P1 findings.
14. **Accessibility & motion** — touch targets < 48dp, missing semantics, contrast, text
    scaling breakage, reduced-motion gaps, animated layout properties, polling that keeps
    running in the background.
15. **Proposed direction (unslop)** — the part that stops this being a lint report:
    - **Character** in one sentence (who this product is for, and how it should feel).
    - **World**: 2–3 concrete references from the product's actual world (jar, water, route,
      doorstep, Bhopal summer), not generic SaaS.
    - **The one or two moments** that carry color and craft on this screen.
    - **Signature detail**: one thing only this product would have.
    - **What stays quiet**: the chrome, the secondary actions, the metadata.
    - **One alternative direction** you rejected and why.
    No implementation. No new dependency. No purple gradients, no glassmorphism, no
    "premium SaaS" default.
16. **Prioritized fix list** — table: `ID | finding | severity P0–P3 | effort S/M/L | files | risk | depends-on`.
    P0 = trust/money/broken flow. P1 = blocks or confuses a real task. P2 = craft. P3 = polish.
17. **Open questions for the owner** — max 5, each one decidable in a sentence. No rhetorical
    questions, no "should we improve UX?".
18. **What must not change** — invariants this screen touches (money math, API contract, auth,
    server-authoritative prices/slots/OTP, accessibility floors, 40 MB APK gate). Name the
    test files that protect them.

---

## WHAT COUNTS AS A REAL FINDING

| Class | Example of a valid finding | Example of an invalid finding |
|---|---|---|
| Spacing | "`checkout` uses `EdgeInsets.all(13)` at `booking_sheet.dart:412` while every sibling card uses 16" | "Spacing feels off" |
| Composition | "`AddressScreen` owns 6 concerns (list, form, map, validation, delete, first-run) in 1456 lines; map picker already exists as its own file" | "Too long, rewrite it" |
| Dead code | "`_formatSlot()` at `tracking_screen.dart:882` has zero callers outside its own file (grep: 1 hit)" | "Looks unused" |
| Flow | "Cancel from tracking returns to Orders but leaves the detail route on the stack; back reopens a cancelled order (`tracking_screen.dart:…`)" | "Flow could be smoother" |
| Copy | "Empty orders says `No data` — no next action, no explanation (`my_orders_screen.dart:…`)" | "Copy is bad" |
| Slop | "Three accents on one card: teal border, green CTA, solar badge (`order_card.dart:…`)" | "Looks AI-generated" |
| States | "Wallet shows ₹0 while loading, so a failed fetch reads as a real zero balance (`donor_wallet_screen.dart:…`)" | "Needs better loading" |

Severity discipline: if it does not change what the user does, it is P2 or lower. Do not
inflate.

---

## ANTI-HALLUCINATION RULES (paste into every subagent)

1. Every claim cites `path:line`, command output, or a screenshot you opened. Otherwise
   prefix with `UNVERIFIED:` and name the command that would settle it.
2. Never describe a screen you have not read or seen. No imagined layouts.
3. Never assume a widget is mounted. Trace it to the tree that builds it.
4. Never call a symbol dead before grepping the whole repo, including tests.
5. Never claim "the design system requires X" without quoting the token and its file:line.
6. Never invent routes, endpoints, states, or copy that do not exist in code.
7. Comments and docs are not truth. If doc and code disagree, log the drift and trust the code.
8. No new dependencies. If a fix truly needs one, name it, price it, and mark it
   `NEEDS-OWNER-DECISION`.
9. Do not propose changing money math, pricing, auth, OTP, API contracts, or test expectations.
   Flag them in section 18 and move on.
10. If the screen is genuinely good, say `KEEP + refinements` and prove it with the audit. That
    is a valid outcome — but the proof is the audit, not the screen's seniority.

---

## ANTI-NOSTALGIA RULES (the owner's explicit instruction)

- Do not treat the previous build as the greatest version. It is a draft.
- Do not preserve a pattern because it already exists. Preserve it only if section 3–14 proves
  it works.
- Do not "improve" by adding. The default fix is deletion, merging, or reordering.
- Do not redesign a working screen to look busy. The unslop rule applies: one bright element,
  quiet chrome, richness in content.
- Do not sand off the product's character to look like a generic fintech app.

---

## STEP 4 — PHASE 2: SYNTHESIS (you, the lead agent, after all 20 files land)

Write three files:

1. **`21-synthesis.md`**
   - Coverage table: every screen → agent → file → status (done / blocked / partial).
   - **Themes**: group findings that repeat across screens (e.g. "every sheet has a different
     footer height", "every list has its own empty state"). A theme that appears 3+ times is a
     system defect, not a screen defect — say so.
   - **Top 10 flow defects** and **top 10 craft defects**, each with the strongest evidence.
   - **Contradictions**: where two agents disagree, state both claims and which one the code
     supports.
   - **What genuinely works** and must survive the redesign.
2. **`22-backlog.md`**
   - One ranked table: `ID | screen | finding | P | effort | files | depends-on`.
   - Group into **implementation slices of one screen each**, ordered: trust/money → blocked
     flows → navigation/state → craft → polish.
   - Cap: P0/P1/P2 get full detail; P3 collapses into a single "later" list.
   - Explicit "do not touch" list (invariants + files outside scope).
3. **`23-owner-decisions.md`**
   - Max 7 decisions, each with a recommendation and the consequence of each option.
   - Examples of the *kind* of decision: language (Hindi/English/bilingual), whether the
     product keeps a photographic hero or goes object-render, whether the vendor app ships in
     the same release train, whether the 5-tab shell stays 5 tabs.

---

## STEP 5 — APPROVAL GATE (hard stop)

Present to the owner, in chat, in this order:

1. The 6 biggest flow defects (one line each + the mermaid before/after).
2. The 5 biggest craft defects.
3. The proposed direction, one line per screen.
4. What will not change.
5. The owner decisions, with your recommendation.

Then **stop**. Do not implement. Wait for explicit approval of the backlog and the direction.
If the owner approves only part, implement only that part.

---

## STEP 6 — CONTEXT SYNC (before you report done)

- `context/progress-tracker.md` — new current-phase entry: audit complete, N findings, top
  themes, next gate.
- `context/decision.md` — append an ADR: why a parallel audit before implementation, why the
  branch, why docs-only, what was rejected (e.g. "redesign from scratch", "let agents edit
  code directly").
- `context/flow.md` — only if the audit produced corrected flow maps; add them under a clearly
  marked "audited 2026-xx-xx" section. Do not rewrite existing flows.
- Do **not** update `context/ui-context.md` yet. Proposed token changes belong in the backlog
  until approved.

---

## DEFINITION OF DONE (audit session)

- [ ] Branch `037-uiux-unslop-audit` exists, branched from a clean tree.
- [ ] `00-index.md`, `00-tokens-actual.md`, `00-slop-signals.md` exist.
- [ ] 20 audit files exist, one per roster row, each with all 18 sections.
- [ ] Every donor screen and vendor screen appears in at least one audit file (coverage table
      in `00-index.md` is complete).
- [ ] Every finding has `path:line` or a screenshot path.
- [ ] `21-synthesis.md`, `22-backlog.md`, `23-owner-decisions.md` exist.
- [ ] `flutter analyze` and `flutter test` results are **identical** to the Phase 0 baseline
      (nothing was changed).
- [ ] Context files updated per Step 6.
- [ ] Docs committed on the branch, not pushed.
- [ ] Approval gate presented and waiting.

---

## APPENDIX A — INVENTORY (verified 2026-10-31)

**Donor app** — 12 `*_screen.dart` screens plus sheets, 59 Dart files, ~22.4k lines in `lib/`.
Largest: `booking_sheet.dart` 1716, `tracking_screen.dart` 1613, `subscription_screen.dart`
1558, `address_screen.dart` 1456, `orders_controller.dart` 1171, `support_screen.dart` 1069,
`plan_builder_sheet.dart` 839, `api_client.dart` 806.

**Vendor app** — 11 features, 30 Dart files, ~6.4k lines in `lib/`.
Largest: `route_screen.dart` 673, `stop_detail_screen.dart` 606, `api_client.dart` 466,
`profile_screen.dart` 450.

A file over ~600 lines is not automatically bad, but it is a **composition suspect**: check
whether it owns more than one job before proposing anything.

## APPENDIX B — INVARIANTS (do not break, do not redesign)

- Server is authority for prices, quotes, delivery slots, OTP, wallet/ledger balances.
  No client-side money math, no fabricated slots, no fake zeros.
- `Idempotency-Key` on order create/cancel/upi-intent/dues-intent; UPI settles by webhook,
  verified by polling order state.
- Delivery OTP is server-owned and only revealed in `assigned`/`dispatched`.
- Money CTA green (`#15803D`) only for Book/Pay/Confirm; green is never navigation or tracking.
- 48dp minimum targets, WCAG AA contrast, safe areas + keyboard insets, explicit
  loading/empty/error/stale/offline/401/submitting states.
- Release APK stays under the 40,000,000-byte gate; no new dependencies without approval.
- Do not touch `workers/api`, `apps/admin_app`, CI, or the release workflow.

## APPENDIX C — USEFUL COMMANDS

```bash
# donor app
cd apps/user_app_donor
flutter analyze
flutter test
flutter run -d chrome --web-port 5599          # visual evidence, login screen is reachable

# per-screen evidence
rg -n "EdgeInsets|SizedBox\((height|width)|fontSize:|Color\(0x|withOpacity|withValues" lib/features/<feature>
rg -n "onPressed: \(\) \{\}|onTap: \(\) \{\}|Future\.delayed|TODO|FIXME" lib/features/<feature>
rg -n "Text\(" lib/features/<feature>          # copy sweep

# dead-code proof (run before calling anything unused)
rg -n "<symbolName>" . --glob '!build/**' --glob '!.dart_tool/**'

# vendor app
cd apps/vendor_app && flutter analyze && flutter test
```

Do not run `flutter build apk` in this session. Do not hit production with real credentials.
Do not create orders. Do not spend money. Do not run paid image generation — the audit may
*propose* a visual with a written prompt, but generating it waits for approval.
