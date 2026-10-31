# X3 — Cross-Cutting: User Flows, State Machines & Navigation Audit

**Scope Audited:**
- Cross-screen routing and navigation graphs for Donor App (`apps/user_app_donor`)
- Operational shift and delivery state machines for Vendor App (`apps/vendor_app`)
- End-to-end user journeys: One-time ordering, dues settlement, delivery completion, and duty management.

---

## 1. Executive Summary
This audit maps the end-to-end navigational flows and state machines across both applications. While state transitions at the network layer are strictly idempotent (guarded by UUID idempotency keys and outbox replay queues), the human navigation architecture suffers from several critical friction points:
1. **The 3-Sheet Booking Labyrinth:** To buy a 20L water can, a customer must open a product detail sheet, which pushes a 1,800-line checkout sheet, which opens a quotation confirmation sheet.
2. **The Disorienting Cross-Tab Dues Redirect:** Paying outstanding dues in the Wallet screen abruptly shifts the bottom navigation shell to the Subscriptions tab without explanatory context.
3. **The Ambiguous Dual-Sheet Vendor Delivery Flow:** Delivery drivers must choose between two disconnected sheets ("Triple" vs "PoD") that ask for overlapping information at the customer's doorstep.
4. **The "Bottom Tab Pops Side Drawer" Anti-Pattern:** The 4th tab on the vendor bottom navigation bar triggers a left-side drawer instead of navigating to a destination.

---

## 2. Donor Flow 1: One-Time Order Booking

### Current Navigation Flow (Nested Sheet Labyrinth)
```mermaid
graph TD
    Home[Customer Home Screen] -->|Tap Can Card| PDS[Product Detail Sheet]
    PDS -->|Tap Order Now| BS[Booking Sheet - 1,800 lines]
    BS -->|Configure Qty / Address / Window| QC[Quote Confirmation Sheet]
    QC -->|Tap Place Order| API[POST /orders]
    API -->|201 Created| OS[Order Confirmed]
    OS -->|Auto-nav| Track[Tracking Screen - Polling Loop]
    Track -->|Delivery Confirmed| Rating[Auto-Popping Rating Sheet]
```
**Defects Identified:**
- 3 nested sheets stacked over the home screen (`Home` -> `ProductDetail` -> `BookingSheet` -> `QuoteConfirm`).
- No 1-tap "Repeat Order" button on Home, despite 20L refill cans being a high-frequency replenishment habit.
- Rating sheet pops up automatically over the tracking screen before the customer has verified their cans.

### Proposed Streamlined Flow
```mermaid
graph TD
    Home[Customer Home Screen] -->|Option A: 1-Tap Reorder| QuickConfirm[Quick Reorder Bottom Sheet - 1 Tap COD/UPI]
    Home -->|Option B: New Booking| UnifiedCheckout[Unified Checkout Sheet - Address + Qty + Window]
    QuickConfirm -->|Confirm| Track[Clean Order Tracking Screen]
    UnifiedCheckout -->|Place Order| Track
    Track -->|Manual Tap| Rating[Rating & Feedback Sheet]
```

---

## 3. Donor Flow 2: Outstanding Dues & Wallet Settlement

### Current Flow (Disorienting Cross-Tab Redirect)
```mermaid
graph TD
    Wallet[Donor Wallet Tab] -->|Notice Dues Warning| DuesCard[Review Dues Button]
    DuesCard -->|Silent Shell Tab Switch| Subs[Subscriptions Tab]
    Subs -->|Scroll to Top| DuesStrip[_DuesStrip Banner]
    DuesStrip -->|Tap Pay Dues| IntentDialog[UPI Payment Intent Alert Dialog]
    IntentDialog -->|Launch Link| UPI[External UPI Application]
    UPI -->|Return to App| Subs
```
**Defects Identified:**
- Tapping "Review dues" in Wallet ejects the user to Tab 2 (Subscriptions) without explaining why dues live on the subscription tab.
- UPI intent resolution happens in a clumsy alert dialog instead of an integrated payment sheet.

### Proposed Flow (In-Context Wallet Settlement)
```mermaid
graph TD
    Wallet[Donor Wallet Tab] -->|Notice Dues| PayDuesBtn[Pay Outstanding Dues Button]
    PayDuesBtn -->|Open Sheet| PaySheet[UPI Payment Intent Sheet]
    PaySheet -->|Open UPI App| UPIApp[PhonePe / GPay / Paytm]
    UPIApp -->|Payment Done| Webhook[Server Webhook Confirms]
    Webhook -->|Instant Sync| WalletUpdated[Wallet Balance & Dues Updated In-Place]
```

---

## 4. Vendor Flow 1: Doorstep Delivery Completion

### Current Flow (Triple vs PoD Confusion)
```mermaid
graph TD
    Route[Route Screen] -->|Tap Stop| StopDetail[Stop Detail Screen]
    StopDetail -->|Driver Dilemma| Fork{Which Button?}
    Fork -->|Driver Picks Triple| Triple[Triple Sheet: Fulls + Empties + Caps + Cash]
    Fork -->|Driver Picks PoD| PoD[PoD Sheet: Customer OTP + Empties + Cash]
    Triple -->|Submit| Return1[Return to Stop Detail]
    PoD -->|Submit| Return2[Return to Stop Detail]
    Return1 -->|Manual Back| Route
    Return2 -->|Manual Back| Route
```
**Defects Identified:**
- Overlapping inputs: both sheets prompt for empty cans returned and cash collected.
- Field drivers are confused about whether "Triple" is mandatory before "PoD".
- After completion, driver must manually pop back to the route list.

### Proposed Flow (Unified Doorstep Handover)
```mermaid
graph TD
    Route[Route Screen] -->|Tap Stop| StopDetail[Stop Detail Screen]
    StopDetail -->|1 Big Action Button| Handover[Handover Sheet]
    Handover -->|Step 1| Cans[Cans: Fulls Given, Empties Taken, Damaged]
    Cans -->|Step 2| Payment[Payment: Collect ₹Cash or Verify Customer OTP]
    Payment -->|Tap Finish| Complete[POST /triple + POST /cash / Outbox Queue]
    Complete -->|Auto-Advance| NextStop[Next Stop Automatically Loaded]
```

---

## 5. Vendor Flow 2: Shift Duty & Navigation

### Current Flow (Duty Hijack & Drawer Anti-Pattern)
```mermaid
graph TD
    Launch[Vendor App Launch] -->|Check onDuty| Gate{Is onDuty true?}
    Gate -->|No| FullDutyScreen[DutyScreen Replaces Whole Scaffold]
    FullDutyScreen -->|Toggle Switch ON| Shell[Vendor Shell Mounts with 4 Tabs]
    Shell -->|Tap Tab 4 'More'| Drawer[Left Navigation Drawer Slides In]
    Drawer -->|Tap Customers / Stock| SubScreen[Pushed Destination Screen]
    Gate -->|Yes| Shell
```
**Defects Identified:**
- Off-duty state completely blocks access to Earnings and past Sync logs.
- Bottom navigation tab "More" opens a side drawer instead of displaying a destination screen.

### Proposed Flow (Accessible Shift Command Center)
```mermaid
graph TD
    Launch[Vendor App Launch] --> Shell[Unified Shell Always Accessible]
    Shell -->|Route Tab| RouteScreen[Route Screen with Top On/Off Duty Banner]
    Shell -->|Stock Tab| StockScreen[Vehicle Inventory Manifest]
    Shell -->|Earnings Tab| EarningsScreen[Commission & Cash in Bag]
    Shell -->|More Tab| MoreGrid[Grid Screen: Customers, Sync Log, Profile, Support]
```

---

## 6. Concrete Actionable Recommendations
1. **Flatten Donor Booking to 1 Sheet:** Eliminate the nested sheet chain (`ProductDetail` -> `BookingSheet` -> `QuoteConfirm`). Use a single unified bottom sheet.
2. **Consolidate Vendor Delivery Completion:** Replace `TripleSheet` and `PodSheet` with a single 2-step `HandoverSheet`.
3. **Keep Wallet Dues In-Context:** Allow users to pay outstanding dues directly inside the Wallet tab.
4. **Eliminate Vendor Side Drawer:** Convert the "More" bottom navigation destination into an authentic screen displaying a touch-friendly grid.
5. **Auto-Advance Vendor Stops:** Upon delivery confirmation, automatically transition to the next assigned stop on the route.

---

## 7. Acceptance Criteria
- [ ] Donor order placement requires at most 1 modal sheet transition.
- [ ] Dues payment is fully executable without leaving the Wallet screen.
- [ ] Vendor delivery completion is executed through a single unified modal.
- [ ] Vendor bottom navigation bar tabs open screens, never a navigation drawer.
- [ ] All underlying state machines remain 100% idempotent and offline-safe.
