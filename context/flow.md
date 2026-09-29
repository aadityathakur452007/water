# Flow — Function Call Map & User Flows

> **Purpose**: The "how it works" file. It maps which functions call what, the user
> journeys, request/response sequences, and routes. Reading this file gives you an
> instant mental model of the project structure.
>
> **Update rule (MANDATORY)**: Update this file whenever you add, rename, or remove any
> function, component, hook, route, API endpoint, or user flow. Never let it go stale —
> agents and humans navigate the codebase through this file.

---

## Overview

[2–3 sentences: what the app does, the main loop, the key actors.]

> **Research note (2026-09-29, Group D)**: no app code exists yet — flows below are
> still template placeholders. The proposed order lifecycle from dev-guide research
> (placed→accepted→picked→packed→assigned→dispatched→delivered, PoD = OTP+photo+
> empties+cash) is documented in `Feature_docs/research/D-dev-guides/_group-D-summary.md`
> and will populate this file's User Flows / Request-Response sections at Series-3
> synthesis. Payment is a separate field, not an order state.

---

## Architecture Diagram

```mermaid
graph TD
    subgraph Client
        U[User Browser]
    end
    subgraph Next.js App
        P[app/ pages] --> F[features/]
        F --> S[shared/]
        F --> E[entities/]
        E --> S
    end
    subgraph Data Layer
        API[Backend API / Server Actions]
        DB[(Database)]
    end
    U --> P
    E --> API
    API --> DB
```

---

## User Flows

> Each flow = one user journey. Format: goal → steps → outcome.

### Flow: Vendor doorstep triple → ledger → evening reconcile (SYN-2 synthesis, proposed)
**Goal**: driver executes per-stop triple offline-tolerant; ledger + dues + reconciliation close the day (see Feature_docs/synthesis/vendor-requirements.md VR-01/02/03/09)
**Steps**: admin auto route+loading sheet → stop: fulls/empties/cash-UPI (queued offline, synced) → ledger mutates (held/deposit/dues, never-negative) → WhatsApp bill + own-bank UPI QR → dues carry forward → evening per-route collection vs pending vs jars-out

```mermaid
flowchart LR
    A([Morning: auto route + loading sheet]) --> B[Stop: given + empties + cash/UPI]
    B --> C[Ledger: held/deposit/dues update]
    C --> D[WhatsApp bill + UPI QR, dues carry forward]
    D --> E([Evening: route-wise reconcile])]
```

### Flow: Bisleri reference — booking → deposit → hold → return → refund (Group E research)
**Goal**: industry-standard jar loop documented for Shodasha adoption (see Feature_docs/research/E-bisleri/_group-E-summary.md)
**Steps**: booking → empty-with-cap declaration → (N−E)×150 deposit → delivery (8-8, no Sun, gate/2F if no lift, Rs3 cap-missing) → hold range / resume ≥24h → Return Jar request → pickup ≤10 working days → wallet refund; disputes ≤3 days

```mermaid
flowchart TD
    A([Booking]) --> B[Declare empties E of N]
    B --> C[Deposit N-E x 150]
    C --> D[Deliver + handover cap check]
    D --> E[Hold/Resume]
    E --> F[Return request + 10-day pickup + refund]
```

### Flow: [User flow name]
**Goal**: [what the user wants]
**Steps**: [brief description]

```mermaid
flowchart LR
    A([User lands on /]) --> B[Browses X]
    B --> C{Has account?}
    C -- no --> D[Sign up]
    C -- yes --> E[Login]
    D --> F[Reaches dashboard]
    E --> F
```

---

## Request / Response Flows

> One sequence diagram per key request. Use the Client → Route → Service → Repository →
> Database chain that matches the actual code.

### [Flow name]
```mermaid
sequenceDiagram
    participant U as User
    participant C as Client (browser)
    participant A as API Route
    participant S as Service
    participant R as Repository
    participant D as Database

    U->>C: submits form
    C->>A: POST /api/x
    A->>S: validate + call service
    S->>R: query
    R->>D: SQL
    D-->>R: rows
    R-->>S: data
    S-->>A: result
    A-->>C: JSON response
    C-->>U: render result
```

---

## Function Call Map

> Which function calls what, per feature. Keep this accurate — agents use it to navigate
> the code and find where changes are needed.

### Feature: [feature name]
```
app/page.tsx (route composition)
  └─ <FeatureComponent />        (features/<feature>/components/)
       └─ use<Feature>Hook()     (features/<feature>/hooks/)
            └─ <feature>Service() (features/<feature>/service/)
                 └─ apiClient.get("/api/...")
```

### Feature: [feature name]
- `[Function A]` calls `[Function B]` to [why]
- `[Function B]` calls `[Repository X]` to [why]

---

## Route Map

| Route | Page / Handler | Purpose | Auth Required |
|-------|----------------|---------|---------------|
| `/` | `app/page.tsx` | Landing page | No |
| `/login` | `app/(auth)/login/page.tsx` | Sign in | No |

---

## API Endpoints

| Method | Path | Handler | Purpose |
|--------|------|---------|---------|
| POST | `/api/auth/login` | `authService.login` | Sign in and issue session |

---

## State Flow

> How state moves through the app (server → client → store). Describe the data flow,
> not just the components.

1. Server component fetches data in `app/` and passes props down
2. Client components call `<feature>Controller` for mutations
3. `queryClient` caches/invalidates on mutations

---

## Update Protocol (MANDATORY)

Update this file when any of the following change:

- [ ] New, renamed, or removed function / component / hook / route
- [ ] Call chain between functions changed
- [ ] New user flow or a change to an existing flow
- [ ] New or removed API endpoint
- [ ] New dependency in a call chain (library, service)
- [ ] State management approach changed

When you update, keep the diagrams in sync with the code — a stale diagram is worse than no diagram.
