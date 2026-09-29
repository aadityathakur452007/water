# Group C Summary — Competitors (CanCan / Rekart / Paniwale / JalSeva)

- **Sources**: C1 cancanindia.com · C2 rekart.io blueprint · C3 paniwale.com · C5 github.com/divyamohan1993/jalseva (C4 not assigned — no source)
- **Read**: 2026-09-29, full fetch (C1, C2, C5 incl. JalSeva source files) + indexed snippets (C3 JS shell)
- **Maps to**: Findings F1, F2, F3, F6, F7, F8

## TL;DR

Group C gives Shodasha three things: a **proven WhatsApp-only repeat mechanic** (CanCan), a **numeric operating blueprint** (Rekart: 2.5–3 jars/customer, Rs 200–300 deposit, RWA 50–200 HH, prepaid wallet), a **subscription price ladder** (Paniwale: Rs 69/jar, Rs 150 deposit, 10/20/30 jars at 10/15/20% off), and a **buildable codebase reference** (JalSeva: OTP auth, 3-tap booking, live tracking, Razorpay sim, domain types). Shodasha's edge: published Rs 28–30 pricing + Rs 150 deposit + pause + arrival window — transparency none of the competitors combine.

## Competitor matrix

| Dimension | C1 CanCan (Chennai) | C2 Rekart (blueprint) | C3 Paniwale (Pune) | C5 JalSeva (capstone) | Shodasha (scope) |
|---|---|---|---|---|---|
| Order channel | WhatsApp-only, no download | App + WhatsApp AI bot | Web + same-day | PWA, 3-tap | Flutter user app + WhatsApp help |
| Repeat mechanic | Predictive one-tap | Subscription / wallet auto-deduct | Prepaid 10/20/30 tiers | 3-tap re-book | One-tap BOOK NOW, last settings |
| Price signal | None published | Rs 40–120 band; wallet | Rs 69/jar published | No tariffs (tanker) | Rs 28 refill / Rs 30 +container |
| Deposit | None published | Rs 200–300 standard | Rs 150, refunded | n/a | Rs 150 exchange |
| Jar ops | Vendor network (opaque) | 2.5–3 jars/cust; balance>3 flag; weekly recon | Return & Repeat at delivery | n/a (tanker) | Exchange stepper + vendor in/out |
| Pause/hold | Not shown | Pause in WhatsApp | Flexible scheduling | Subscriptions typed | One-tap pause/resume |
| Tracking | Concierge alerts | Driver app + dashboard | Same-day promise | Live GPS map | Arrival window (no live dot) |
| Pay | In-chat favourite app | Wallet + links + B2B postpaid | Prepaid | Razorpay sim (UPI/cards) | UPI + COD |
| Vendor side | Portal dashboard | Driver app + zones | Routes (inferred) | Supplier dashboard | Flutter vendor app |
| Scale claim | 500+ cust / 50+ vendors / 10k orders | 100–200/zone; manual breaks 50–75 | Pune-wide | Demo | Phase-1 households |

## What Shodasha copies (adopt 1:1 or near)

1. **CanCan one-tap predictive repeat** → home BOOK NOW with pre-selected settings. (C1)
2. **wa.me prefilled deep links** for help, confirmations, shareable bills. (C1)
3. **Rekart jar discipline**: 2.5–3 jars/customer stocking, per-stop in/out logging, flag above ~3 outstanding, weekly reconciliation. (C2)
4. **Rekart vendor stop flow**: sequenced route → qty/stop → confirm → empties → cash, synced live. (C2)
5. **Paniwale Rs 150 deposit + Return & Repeat at delivery** — identical figure, same handover mechanic. (C3)
6. **JalSeva auth + booking skeleton**: phone OTP, role split, server-verified session; location → qty → pay 3-tap; payment state guards. (C5)
7. **JalSeva domain types** as model seed (Order/Tracking/Payment/SubscriptionPlan/DeliveryVerification). (C5)
8. **Concierge status language** (CanCan alerts / JalSeva ONDC stages) → arrival-window + confirmation copy. (C1, C5)

## What Shodasha differentiates (deliberate departures)

1. **Published pricing (Rs 28/30)** — CanCan hides prices; Rekart band is 40–120; Paniwale is Rs 69 premium. Transparency = trust in a low-price market.
2. **Rs 150 vs Rs 200–300 deposits** — lower entry barrier; compensated by threshold + pause discipline from Rekart.
3. **Arrival window, no live dot** — cheaper to build and operate than JalSeva GPS; rider name + call covers the anxiety.
4. **UPI + COD (no wallet v1)** — matches household cash habits; wallet/postpaid deferred with fields reserved.
5. **Pause as first-class one-tap** — Bisleri-validated, Paniwale only hints at flexibility.
6. **Three native surfaces** (2× Flutter + Next.js admin) vs CanCan portal-web / JalSeva single-codebase — each actor gets a minimal tool.

## Open verifications (carry to Series-3 / primary research)

- C1 counters (500+/50+/10k/4.9) and in-chat pricing/SLA — mystery-shop the wa.me link.
- C3 page body + refund/pause mechanics — in-browser confirm (JS shell blocked fetch).
- Shodasha Rs 28–30 vs local refill reality — survey before pricing lock (existing open question).
- JalSeva performance/i18n claims — README assertions, not tested.
