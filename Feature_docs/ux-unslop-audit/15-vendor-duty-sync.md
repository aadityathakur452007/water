# V3 — Vendor Duty, Outbox Sync & Cascade Motion Audit

**Files Audited:**
- `apps/vendor_app/lib/features/duty/duty_screen.dart` (160 lines)
- `apps/vendor_app/lib/features/duty/duty_controller.dart`
- `apps/vendor_app/lib/features/sync/sync_screen.dart` (151 lines)
- `apps/vendor_app/lib/features/sync/sync_controller.dart`
- `apps/vendor_app/lib/core/cascade.dart` (115 lines)

---

## 1. Executive Summary
The Duty, Sync, and Cascade subsystems govern driver operational shifts, offline queue synchronization, and performant list animations. This domain contains several of the cleanest architectural decisions in the codebase: a custom, zero-dependency staggered list animation engine (`cascade.dart`) with built-in OS reduced-motion guards, an honest outbox queue that replays offline deliveries idempotently, and destructive off-duty guards that repool remaining route stops back to the central dispatcher. However, the interface suffers from unrefined string parsing, raw ISO timestamp leaks, and layout minimalism that feels unfinished:
1. **Raw ISO timestamp leaks in sync queue:** `sync_screen.dart:121` renders queue metadata as: `Stop #14 • queued 2026-10-31T06:12:45.123Z`. Raw ISO 8601 UTC strings should never be presented to field drivers in Bhopal.
2. **Fragile string-scraping for UI status tones:** `sync_screen.dart:73-85` determines icon shape and color by running string checks on the error message: `c.result!.contains('Network')` and `c.result!.contains('fail')`. Any minor copy change on the backend breaks icon and color styling.
3. **Bilingual slash headers:** `Duty / ड्यूटी` (`duty_screen.dart:40`) and `Sync / सिंक` (`sync_screen.dart:39`) perpetuate the slash-separated dual language pattern.
4. **Under-leveraged motion system:** While `cascade.dart` provides an exceptional, test-safe staggered entrance animation, it is restricted to the route list and absent from duty and sync lists.

---

## 2. Screen Identity & Canonical Route
- **Duty Screen:** Full-screen duty gate shown when vendor is off-duty, or pushed from drawer/menu.
- **Sync Screen:** Pushed route (`_push(SyncScreen)`) from drawer or route card counter.
- **Cascade Scope:** Animation wrapper for staggered entrance of list children.
- **Target Persona:** Delivery driver starting or ending their shift, or inspecting why an offline delivery receipt has not yet uploaded.

---

## 3. Visual & Spatial Hierarchy
### Duty Screen
- **AppBar:** Title "Duty / ड्यूटी".
- **Shift Status Card:** Large card featuring:
  - Duty toggle switch (On Duty vs Off Duty).
  - Shift start duration (`Since: ...`).
  - Repooled stops notice (`N stops wapas pool mein`).
  - Stops progression meter (completed vs max stops) with `LinearProgressIndicator`.
  - Cash custody and empty jar custody meters.

### Sync Screen
- **AppBar:** Title "Sync / सिंक".
- **Result Banner:** `blueTint` card displaying the outcome of the latest sync run.
- **Action CTA:** Prominent button "Abhi sync karein (N)" triggering `syncNow()`.
- **Queue List:** Outbox cards for pending offline deliveries.
- **Rejected List:** Red-tinted cards for server-rejected stops with a "Hatayein" (discard) action.

---

## 4. Color & Contrast Audit

| Element | File:Line | Color Token / Value | Contrast Ratio (vs BG) | Compliance / Finding |
|---|---|---|---|---|
| Screen Background | `duty_screen.dart:39` | Standard theme bg | Baseline | Standard light surface |
| Duty Switch Active | `duty_screen.dart:92` | `ShodashaTheme.blue` (`#1A56DB`) | 5.8:1 vs surface | Clear active state |
| Error Icon Ground | `duty_screen.dart:57` | `ShodashaTheme.danger` (`#DC2626`) | 5.2:1 vs surface | High visibility alert |
| Progress Bar Track | `duty_screen.dart:147` | `ShodashaTheme.border` | Subtle bar | Clear progress demarcation |
| Progress Bar Active | `duty_screen.dart:148` | `ShodashaTheme.blue` | 5.8:1 vs surface | High contrast indicator |
| Sync Result Banner | `sync_screen.dart:66` | `ShodashaTheme.blueTint` | 1.15:1 vs ground | Informational container |
| Sync Pending Icon | `sync_screen.dart:115` | `ShodashaTheme.blue` | 5.8:1 vs surface | Clear pending signal |
| Sync Rejected Icon | `sync_screen.dart:132` | `ShodashaTheme.danger` | 5.2:1 vs surface | Strong error signal |

---

## 5. Typography & Text Scale

| Text Element | File:Line | Font Size | Weight | Finding |
|---|---|---|---|---|
| Duty AppBar Title | `duty_screen.dart:40` | Default (20px) | Default | Bilingual slash title |
| Shift Status Headline | `duty_screen.dart:86` | 18px | w700 | Clear status anchor |
| Shift Shift Since | `duty_screen.dart:125` | Default (14px) | Default | Subtitle copy |
| Meter Ratio Labels | `duty_screen.dart:140` | Default (14px) | Default | Numeric capacity breakdown |
| Sync Action Button | `sync_screen.dart:104` | Default (14px) | Default | Button text with dynamic counter |
| Queue Card Title | `sync_screen.dart:116` | Default (16px) | w600 | Clear stop ID header |
| Queue Card Subtitle | `sync_screen.dart:121` | Default (14px) | Default | **Raw ISO timestamp leak** |

---

## 6. Spacing, Grid & Alignment
- **Duty Screen Padding:** `EdgeInsets.all(16)` with card padding `EdgeInsets.all(20)`.
- **Sync Screen Padding:** `EdgeInsets.all(16)` with cards separated by `SizedBox(height: 12)`.
- **ListTile Ergonomics:** Both pending queue tiles and rejected tiles explicitly declare `minTileHeight: ShodashaTheme.minTarget` (`sync_screen.dart:113, 130`), ensuring accessible 48dp+ tap areas.

---

## 7. Micro-Interactions, Feedback & States
- **Destructive Off-Duty Confirmation:** Turning the duty switch OFF while on-duty triggers an alert dialog: "Duty off karein? Baki stops aaj ke liye ruk jayenge." (`duty_screen.dart:96-118`).
- **Repooling Accountability:** After turning duty off, the screen renders exact repooled stop count (`lastRepooled > 0`), ensuring complete transparency about undelivered jars.
- **Manual Sync Trigger:** "Abhi sync karein (N)" button triggers single-flight queue synchronization with busy spinner label "Sync ho raha…".
- **Stale Replay Discard:** Stuck server rejections (e.g. `STALE_STOP`) render a "Hatayein" action button to purge obsolete replay records from local storage (`sync_screen.dart:140-144`).

---

## 8. Motion & Transitions
- **Cascade Animation (`cascade.dart`):**
  - Staggered entrance controller using `Interval(begin, 1.0, curve: Curves.easeOut)`.
  - Zero external timers (`Ticker`-based, widget-test safe).
  - Strict OS accessibility check: `MediaQuery.disableAnimationsOf(context)` immediately returns the static child.
- **Switch Interaction:** Native smooth sliding toggle transition for duty state.

---

## 9. Cognitive Load & Information Scent
- **Cryptic ISO Dates:** Drivers reading `queued 2026-10-31T06:12:45.123Z` cannot easily discern whether an item was queued 2 minutes ago or 2 hours ago. Needs relative time formatting ("2 mins ago").
- **Meters Overload:** Presenting Stops meter, Jars Allocated meter, Cash Custody meter, and Empty Jar Custody meter on a single plain card dilutes focus. Grouping into "Deliveries" vs "Cash & Stock" creates clearer mental models.

---

## 10. Touch Targets & Ergonomics
- **Duty Switch:** Full-size toggle switch placed on right side of card, easily reachable with right thumb.
- **Sync Now CTA:** Full-width `ElevatedButton.icon` with 48dp height.
- **Discard Action:** `TextButton` on rejected cards provides adequate tap padding.

---

## 11. Edge Cases & Resiliency
- **Network Failure During Sync:** Caught gracefully; sync status banner updates to explain network outage without losing local queue items (`sync_screen.dart:73-85`).
- **Mid-Route Departure:** Off-duty transition reliably repools undelivered orders to the server.
- **Empty Outbox:** When queue and rejected items are empty, displays clean reassurance: "Sab synced — koi pending entry nahi".

---

## 12. Code-Level Craft & Tech Debt

| File & Line | Issue | Severity | Proposed Fix |
|---|---|---|---|
| `sync_screen.dart:121` | Raw ISO UTC timestamp `queued ${q.queuedAtIso}` shown | High | Replace with relative time format (e.g. "5 min pehle") |
| `sync_screen.dart:73-85` | Fragile string scraping (`contains('Network')`) for UI tones | High | Use structured enum or response code on sync controller |
| `duty_screen.dart:40` | Slash-separated bilingual header `Duty / ड्यूटी` | Medium | Use clean Hindi or English title |
| `duty_screen.dart:148` | Hardcoded `ShodashaTheme.blue` instead of progress token | Low | Standardize progress bar colors |
| `cascade.dart` | Staggered motion limited to Route, absent from other screens | Low | Reuse `CascadeScope` across Duty and Sync screens |

---

## 13. Accessibility (a11y)
- **Reduced Motion Support:** `cascade.dart:99` checks `MediaQuery.disableAnimationsOf(context)` and disables all slide/fade transitions when enabled by OS.
- **Minimum Target Guarantee:** Sync list tiles explicitly enforce `minTileHeight: ShodashaTheme.minTarget` (48dp).
- **High Contrast Status Icons:** Icons pair with descriptive text labels.

---

## 14. Cross-Platform Consistency
- **InheritedWidget Architecture:** `CascadeScope` uses standard Flutter `InheritedWidget` state distribution, behaving identically on Android, iOS, and Web.
- **SharedPreferences Queue:** Outbox queue serializes to JSON strings in local storage, resilient across app restarts.

---

## 15. Proposed Layout & Unslop Direction
### Duty Screen: "The Shift Dashboard"
- **Operational Status Hero:**
  - Clear state badge: "🟢 ON DUTY" or "⚪ OFF DUTY".
  - One-tap switch with confirmation prompt.
- **Two Focused Progress Cards:**
  - Card 1: **Deliveries Manifest** (`18/32 Stops Completed • 24 Jars Delivered`).
  - Card 2: **Cash & Inventory Custody** (`₹2,400 Cash in Bag • 18 Empties on Truck`).
- **Clean Title:** "Duty Status" or "ड्यूटी स्थिति" (no slashes).

### Sync Screen: "Transparent Outbox Manager"
- **Relative Time Stamps:** Format queue dates as "2 min pehle", "10 min pehle".
- **Structured Status Cards:** Color-code cards based on controller status enum (`SyncStatus.offline`, `SyncStatus.error`, `SyncStatus.synced`).

---

## 16. Concrete Actionable Recommendations
1. **Format Queue Timestamps:** Replace `q.queuedAtIso` in `sync_screen.dart:121` with a friendly relative time helper ("Abhi", "X min pehle").
2. **Eliminate String-Scraping for Icons:** Update `SyncController` to expose a structured enum (`SyncResultTone.networkError`, `SyncResultTone.rejected`, `SyncResultTone.success`) rather than checking `c.result!.contains(...)`.
3. **Clean Up Slash Titles:** Remove slashes from `Duty / ड्यूटी` and `Sync / सिंक`.
4. **Structure Duty Meters:** Divide the single cluttered duty card into two distinct sections: "Deliveries" and "Cash & Stock Custody".
5. **Apply Cascade Staggering to Sync Queue:** Wrap sync queue items in `CascadeScope` to provide the same polished entrance animation present on the route screen.

---

## 17. Acceptance Criteria
- [ ] No raw ISO timestamps are visible to drivers in the sync outbox.
- [ ] UI status tones derive from structured status enums, never from string scraping.
- [ ] Reduced motion preferences are strictly respected across all animated elements.
- [ ] Off-duty transitions continue to safely repool undelivered stops to dispatch.
- [ ] Offline queue replay remains completely idempotent with zero duplicated deliveries.

---

## 18. File Invariants & Verification Checklist
- [x] Invariant: Off-duty transition repools pending stops to dispatch (`duty_controller.dart:96-120`).
- [x] Invariant: Outbox queue stores pending operations offline and replays them upon connectivity (`sync_controller.dart:100-115`).
- [x] Invariant: Reduced motion support verified in `cascade.dart:99`.
- [x] Verified: Rejected delivery records provide a clean discard mechanism to prevent queue gridlock.
