# User Flows — Shodasha User App ↔ Vendor App ↔ Admin Web (v1)

- **Scope**: Flutter Android user app flows with vendor-app and super-admin counterparts. No code.
- **Conventions**: `U-` = user-app step · `V-` = vendor/delivery-app step · `A-` = super-admin (Next.js) step. Windows are 30-min arrival windows inside 8 AM–8 PM, ex-Sun/holidays; default = kal subah (next working day). Deposit = `(N−E)×150`, refundable; cap-missing = +Rs 3/jar (E2). UPI + COD in v1 (deliberate diverge from Bisleri no-COD).
- **Req links**: UR-IDs refer to `user-requirements.md`.

---

## 1. First order (new user: see price → trust → OTP → address → pay → confirm)

Covers UR-02/03/04/05/06/07/08/09/11/12/13/14/21/23. Sources: A1 (no-wall quote, named SKUs), A2/A3 (proof strip), A5/C5 (OTP), E1/E2 (empties, deposit, next-day, pincode).

```mermaid
flowchart TD
    subgraph UAPP[User app - Flutter Android]
        U1([New user opens app]) --> U2[See prices WITHOUT login<br/>Refill Rs28 / Jar+Container Rs30]
        U2 --> U3[Quality trust line<br/>RO+UV + lab date + report]
        U3 --> U4[Adjust steppers ON cards<br/>default 2 jars]
        U4 --> U5[Empty-exchange stepper E<br/>Rs150 refundable note + live N-E x 150]
        U5 --> U6[Address + GPS + pincode check]
        U6 --> U7{Serviceable?}
        U7 -- No --> U8[BOOK NOW disabled<br/>not servicing + WhatsApp help]
        U7 -- Yes --> U9[Pick window: default kal subah<br/>8-8 ex-Sun/holiday]
        U9 --> U10[Quote lock shown<br/>water + deposit + cap note]
        U10 --> U11[OTP login: phone + 6-digit]
        U11 --> U12[UPI/COD chips + Confirm]
        U12 --> U13[Confirmation: ID + time + amount<br/>shareable to WhatsApp]
    end
    subgraph VAPP[Vendor app]
        V1[Stop created: address + N in + E out + cash due]
    end
    subgraph ADMIN[Super-admin web]
        A1[Order in queue + zone assignment<br/>deposit ledger entry]
    end
    U12 --> A1 --> V1
    V1 -. window + rider name .-> U13
```

```mermaid
sequenceDiagram
    participant U as User app
    participant A as Admin/API
    participant V as Vendor app
    U->>A: booking (N, E, address/GPS/pincode, window, pay mode)
    A->>A: pincode check + deposit=(N-E)*150 + quote freeze
    A->>V: stop (address, jars in/out, cash due, lift flag)
    V-->>A: accept + rider assigned
    A-->>U: confirmation (ID + window + amount + rider on assign)
```

---

## 2. Repeat 1-tap (2 jars default, kal subah)

Covers UR-01/02/07/13/14/25. Sources: A1 (3-tap repeat, quote-before-commit), C1 (predictive one-tap), C5 (location → size → pay skeleton).

```mermaid
flowchart TD
    subgraph UAPP[User app]
        R1([Opens app - water low]) --> R2[Home = booking screen<br/>last qty + address + window preselected]
        R2 --> R3{Tweak?}
        R3 -- No --> R4[BOOK NOW - 1 tap]
        R3 -- Yes --> R5[Adjust steppers / empties / window / UPI-COD]
        R5 --> R4
        R4 --> R6[Quote lock re-shown]
        R6 --> R7[Confirm]
        R7 --> R8[ID + time + amount + window]
    end
    subgraph ADMIN[Admin]
        A1[Duplicate last settings<br/>re-price pre-confirm only]
    end
    subgraph VAPP[Vendor app]
        V1[New stop queued at quoted price]
    end
    R7 --> A1 --> V1
```

---

## 3. Tracking — 30-min window (no live dot)

Covers UR-09/10/18. Sources: A1 (window beats dot, map only near arrival), A5 (push windows), D4 (lifecycle + ETA-to-window).

```mermaid
flowchart TD
    subgraph UAPP[User app]
        T1([Order confirmed]) --> T2[4-step tracker<br/>Confirmed - Packed - On the way - Delivered]
        T2 --> T3[30-min window e.g. 9:00-9:30 AM<br/>+ rider name + Call button]
        T3 --> T4{Window change?}
        T4 -- Yes --> T5[Push + in-card update with reason]
        T5 --> T3
        T4 -- No --> T6{Delivered?}
        T6 -- No --> T3
        T6 -- Yes --> T7[Shared record + receipt<br/>empties handed over]
    end
    subgraph VAPP[Vendor app]
        V1[Accept - pick - pack - dispatch<br/>GPS active-job only] --> V2[Mark delivered + empties in + cash]
    end
    subgraph ADMIN[Admin]
        A1[Canonical lifecycle<br/>placed-picked-packed-assigned-dispatched-delivered<br/>reassign keeps quoted price]
    end
    V1 --> A1 -. steps + window .-> T2
    V2 -. completion .-> T7
```

---

## 4. Pause / resume (incl. ≥24h cutoff + auto-resume)

Covers UR-15/16. Sources: A5 (calendar self-service), E1 (hold range + resume ≥24h + pick date).

```mermaid
flowchart TD
    subgraph UAPP[User app]
        P1([Going away]) --> P2[One-tap Pause under BOOK NOW / order card]
        P2 --> P3[Pick hold date range + optional return date + Confirm]
        P3 --> P4[Push: Paused till date]
        P4 --> P5{Return date set?}
        P5 -- Yes --> P6[Auto-resume fires<br/>push: Deliveries resumed]
        P5 -- No --> P7[Manual Resume]
        P7 --> P8{>=24h before delivery?}
        P8 -- No --> P9[Blocked: resume 24h before<br/>offer next valid date]
        P9 --> P7
        P8 -- Yes --> P10[Pick preferred delivery date + Activate]
        P6 --> P11[Last settings intact]
        P10 --> P11
    end
    subgraph ADMIN[Admin]
        A1[Hold flag: exclude from routing<br/>resume re-queues stop]
    end
    subgraph VAPP[Vendor app]
        V1[Route drops paused stops<br/>re-added on resume]
    end
    P3 --> A1 --> V1
    P10 --> A1
    P6 --> A1
```

---

## 5. Payment — UPI / COD (guards + reconcile + reminders)

Covers UR-13/14/24. Sources: D4 (invoice links, cash entry → admin, dues reminders, 409/expired/partial/offline branches), C5 (create/verify guards, idempotency), E-group (deposit ledger; wallet = v2).

```mermaid
flowchart TD
    subgraph UAPP[User app]
        Y1([Quote locked]) --> Y2{UPI or COD?}
        Y2 -- UPI --> Y3[UPI intent + idempotency key]
        Y3 --> Y4{Result?}
        Y4 -- Paid --> Y5[Confirmation paid<br/>bill + WhatsApp share]
        Y4 -- Failed / expired link --> Y6[Reissue pay-link<br/>quote intact, retry]
        Y6 --> Y3
        Y4 -- 409 already-paid --> Y5
        Y2 -- COD --> Y7[Confirm: Pay cash at door<br/>deposit-due-at-door line]
        Y7 --> Y8[Bill shows dues until vendor sync]
    end
    subgraph VAPP[Vendor app]
        V1[Cash collected at stop<br/>queued offline if no data] --> V2[Sync on reconnect]
    end
    subgraph ADMIN[Admin]
        A1[Reconcile order vs cash vs UPI txns<br/>dues carry-forward + low-balance reminders]
    end
    Y5 --> A1
    Y8 --> V1 --> V2 --> A1 -. dues update .-> Y8
```

```mermaid
sequenceDiagram
    participant U as User app
    participant A as API/Billing
    participant V as Vendor app
    U->>A: pay intent (idempotency key) / COD confirm
    A-->>U: paid / pay-link / COD-due bill
    V->>A: PATCH cash received (or queued offline → sync)
    A->>A: reconcile + flag dues
    A-->>U: dues / low-balance reminder push
```

---

## 6. Complaint / dispute (≤3-day window, WhatsApp + call)

Covers UR-19/20. Sources: E2 (3-day window → adapt channel), D4 (recovery = retention), C1 (thread alerts).

```mermaid
flowchart TD
    subgraph UAPP[User app]
        C1([Delivered - issue?]) --> C2[Rating prompt: low score offers Raise complaint]
        C2 --> C3{Within 3 days?}
        C3 -- No --> C4[Window expired<br/>show hours + WhatsApp help]
        C3 -- Yes --> C5[Report issue: reason code + text<br/>order pre-attached, photos v2]
        C5 --> C6[Ticket status: open - in progress - resolved]
        C6 --> C7[Resolution push + in-app update]
    end
    subgraph ADMIN[Super-admin]
        A1[3-day dispute queue<br/>ticket + record + rider note] --> A2[Resolve / refund / redelivery<br/>escalate if SLA breached]
    end
    subgraph VAPP[Vendor app]
        V1[Rider note / redelivery stop if ordered]
    end
    C5 --> A1
    A2 --> V1
    A2 -. resolution .-> C7
```

---

## 7. Return jar (qty + address + landmark, 10-working-day SLA)

Covers UR-22/05/06. Sources: E1 FAQ-5 (flow + SLA + eligibility), E2 (deposit ledger, cap check), A2 (dormant-asset states).

```mermaid
flowchart TD
    subgraph UAPP[User app]
        J1([Profile - Return Empty Jar]) --> J2[Enter qty + address + landmark + Submit]
        J2 --> J3[Confirm: Pickup within 10 working days<br/>request ID + refund-via-UPI note]
        J3 --> J4[History: requested - picked - refunded]
    end
    subgraph ADMIN[Super-admin]
        A1[10-day return queue<br/>deposit ledger per jar<br/>eligibility check: online-deposit jars only] --> A2[Refund via UPI/manual<br/>wallet in v2]
    end
    subgraph VAPP[Vendor app]
        V1[Pickup stop: collect empties<br/>check caps M x Rs3] --> V2[Mark picked + handover count]
    end
    J2 --> A1 --> V1 --> V2 --> A2 -. refunded .-> J4
```

---

## Cross-flow notes (vendor ↔ admin contracts, user-app visible effects)

| # | Contract | User-visible effect |
|---|----------|---------------------|
| 1 | Reassignment keeps quoted price (A1/D4) | Price on confirmation never changes after confirm |
| 2 | GPS active-job only; no live dot in user app (A1/C5-adapt) | Window + rider name + call instead of moving marker |
| 3 | Address edit syncs to stop pre-dispatch (A5) | Mid-order edit either propagates or is blocked with message |
| 4 | COD cash entry → admin reconcile (D4) | COD bill flips to paid/dues after vendor sync |
| 5 | Deposit ledger per jar; offline-brand empties = no refund + reason (E1-adapt) | Handover shows accepted vs rejected empties with reason |
| 6 | Sunday/holiday + lift gate-2F rules (E2) | Window picker + confirm copy + vendor stop instruction stay consistent |
