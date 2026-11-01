# Agent Brief — Read This Before Auditing

Repo: `C:\Users\Hp\Water`. Branch: `037-uiux-unslop-audit`. This is a **read-only audit**.
You write exactly one markdown file. You do not edit app code, tests, config, CI, or another
agent's file. You do not commit.

## Read first, in this order

1. `C:\Users\Hp\.config\opencode\skills\unslop\SKILL.md` + `references/signs.md` +
   `references/tokens.md`. Apply them; do not summarize them.
2. `context/ui-context.md` and `States.md` (repo root).
3. `Feature_docs/ux-unslop-audit/00-tokens-actual.md` and `00-slop-signals.md`.
4. Your assignment files, plus the app's `lib/core/theme.dart` and `lib/shared/ui/*`.
5. Only if your scope needs it, grep `context/decision.md` / `context/flow.md`. Do not read
   them in full (they are 150–470 KB).

Open `Feature_docs/ux-unslop-audit/shots/donor-login-390.png` only if your scope includes
the login screen. Otherwise your header must say `VISUAL: not captured — code audit`.

## Evidence law (non-negotiable)

- Every claim cites `path:line`, command output, or a screenshot you actually opened.
- If you cannot verify it, write `UNVERIFIED: <exact command that would settle it>`.
- Never describe a screen you have not read. Never assume a widget is mounted; trace it to
  the tree that builds it.
- Never call a symbol dead before grepping the whole repo, including tests.
- Never claim "the design system requires X" without quoting the token and its `file:line`.
- Comments and docs are not truth. If doc and code disagree, log the drift and trust code.
- No new dependencies. Do not propose changes to money math, pricing, auth, OTP, API
  contracts, or test expectations. Flag those in section 18 and move on.
- If the screen is genuinely good, write `KEEP + refinements` and prove it. That is a valid
  outcome.

## Severity discipline

P0 = trust/money/broken flow. P1 = blocks or confuses a real task. P2 = craft. P3 = polish.
If it does not change what the user does, it is P2 or lower. Do not inflate.

## Output: exactly these 18 numbered sections, in this order

Tables over prose. No filler. Target 250–500 lines. Every table row needs `file:line`.

1. **Header** — screen(s), file paths + line counts, routes/entry points, agent, date,
   evidence status (`screenshots: yes/no`).
2. **Job to be done** — one paragraph: what the user is trying to finish here, and the one
   moment that must feel good. No marketing language.
3. **What the code actually renders** — widget tree in 10–20 lines, plus every state the
   screen can be in. Cite the file that owns each state.
4. **Interaction inventory** — table: `trigger | handler | state change | result/navigation |
   file:line`. Every tap, long-press, swipe, scroll-triggered load, pull-to-refresh, back
   press, keyboard action. Missing handlers are findings too.
5. **Flow map** — mermaid `flowchart`: entry points in, exits out, dead ends, loops. Mark
   each confusing/unnecessary edge.
6. **Slop audit** — table: `sign | where (file:line) | why it reads AI-generated | verdict`.
   Use the unslop `signs.md` list. No invented gradients — this codebase has none.
7. **Spacing & layout audit** — table: `element | current value (file:line) | token it
   should use | proposed`. Real numbers from `EdgeInsets`, `SizedBox`, `padding`, `gap`.
   Flag every value off the 4/8/12/16/24/32 scale and every inconsistent sibling.
8. **Type & color audit** — same table shape. Flag screen-local hex, `withOpacity`, raw
   `fontSize`, weight soup, contrast failures, second token system.
9. **Component audit** — three lists: (a) should be a shared primitive, (b) duplicated
   across screens, (c) wrong composition (more than two things collaborating on one job,
   sheets owning business logic, widgets re-implementing `shared/ui`, state spread across
   3+ owners). For each: the smallest structural fix, not a rewrite.
10. **Logic & flow defects** — wrong order, redundant steps, missing confirmation/undo,
    silent failure, optimistic UI that lies, navigation traps, double submission, stale
    reads, retry that duplicates a write, keyboard covering the CTA, back losing input.
11. **Dead / for-show code** — table: `symbol | file:line | callers found | verdict (dead |
    for-show | test-only | keep)`. Unused params, unread controller fields, empty callbacks,
    fake `Future.delayed` loading, hardcoded lists/prices/names, comments describing removed
    code. Grep each symbol including tests first.
12. **Copy audit** — table: `current string | file:line | problem | proposed`. Titles,
    buttons, empty states, errors, confirmations. Ban raw status codes, internal jargon,
    shouting, unverified claims.
13. **States matrix** — rows: loading, empty, error (network), error (server), stale,
    offline, 401/403, validation, submitting, success. Columns: `present? | where | honest?
    | gap`. Missing applicable states are P1.
14. **Accessibility & motion** — touch targets <48dp, missing semantics, contrast, text
    scaling breakage, reduced-motion gaps, animated layout properties, polling that keeps
    running in the background.
15. **Proposed direction (unslop)** — character in one sentence; world with 2–3 concrete
    references from the product's actual world (jar, water, route, doorstep, Bhopal
    summer); the one or two moments that carry color/craft on this screen; one signature
    detail only this product would have; what stays quiet; one alternative direction you
    rejected and why. No implementation. No dependency. No purple gradients.
16. **Prioritized fix list** — table: `ID | finding | severity P0–P3 | effort S/M/L | files |
    risk | depends-on`.
17. **Open questions for the owner** — max 5, each decidable in one sentence. No rhetorical
    questions.
18. **What must not change** — invariants this screen touches (money math, API contract,
    auth, server-authoritative prices/slots/OTP, accessibility floors, 40 MB APK gate).
    Name the test files that protect them.

## Anti-hallucination reminders

- Do not invent routes, endpoints, states, copy, or layouts that are not in code.
- Do not assume a widget is reachable because it is defined.
- Do not call a hardcoded value a "placeholder" without checking whether the server owns it.
- Vendor app has no type/spacing scale; audit consistency, not donor's scale.
- The donor login screenshot is the only captured visual. Everything else is code evidence.
