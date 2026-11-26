# Project Name

> [Short tagline — 1 sentence describing what this project does]

## Tech Stack

[Replace with your tech stack]

- **Framework**: Next.js 16 + TypeScript
- **Styling**: Tailwind CSS v4 + shadcn/ui
- **Animation**: Motion (Framer Motion), GSAP
- **UI Library**: Mixed from DESIGN.md — Astryx, Animata, Skipper UI, etc.
- **Package Manager**: npm or pnpm

## Getting Started

```bash
# Install dependencies
npm install

# 1. Install skills (AI agent design/development skills)
python Skills.py

# 2. Install Spec Kit (SDLC workflow commands — run AFTER Skills.py)
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@latest
specify init .

# Run development server
npm run dev
```

## Project Structure

```
├── .agents/         # AI agent skills (embedded + installed)
│   ├── tech-selection/         # Decide the tech stack
│   ├── sitemap/                # Map pages/routes/hierarchy
│   ├── user-flows/             # User journeys + request/response flows
│   ├── folder-structure/       # Derive + scaffold folder structure
│   ├── design-patterns/        # Architecture, patterns, request flow, production
│   ├── ssdlc/                  # Secure Software Development Lifecycle
│   ├── design-basics/
│   ├── premium-design/
│   ├── performance_engineering/
│   └── ui-checklist/
├── context/         # Project context files (fill these in)
│   ├── progress-tracker.md   # Where the project is (phase, done, next) — update every task
│   ├── flow.md               # How it works — function call maps, user flows, routes
│   └── decision.md           # Why it's built this way — every decision + rationale
├── src/             # Application source code (feature-first)
│   ├── app/         # Next.js App Router
│   ├── features/    # Feature modules (model/config/service/controller/repository)
│   ├── shared/      # Shared UI, hooks, utilities
│   └── entities/    # Domain models
├── Agent.md         # Agent execution protocol
├── DESIGN.md        # Curated component library references
├── SKILLS.md        # Master skill index — find the right skill
├── Skills.py        # Skill installer
└── README.md        # This file
```

## Design Resources

- **DESIGN.md** contains the curated list of allowed component libraries and design tools
- **Astryx (Meta)** is the primary reference for production-grade components
- Premium animated libraries: Animata, Cult UI, Skipper UI, React Bits Pro, etc.

## Skills

Skills are in `.agents/`. **First read `SKILLS.md`** (the master index) to find the
right skill for what you're building. Then run `python Skills.py` to install the
community skills. See `.agents/AGENTS.md` for details.

**After running Skills.py, you MUST also run specify to install the SDLC workflow commands:**

```bash
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@latest
specify init .
```

This unlocks the `/speckit.*` commands (speckit.specify, speckit.plan, speckit.tasks, etc.).

## Structuring a New Project

After `npm install` (create-app boilerplate), impose this project's hierarchy on it.
Load the `folder-structure` skill (`.agents/folder-structure/`) and materialize its
canonical tree for your stack — feature-first frontend, controller-service-repository
backend, or the fullstack/mobile/monorepo variants. Only create folders the product
actually needs; let the feature-first pattern grow the tree.

## Essential Skills (in `.agents/`)

| Skill | What it does |
|-------|--------------|
| `tech-selection` | Decide the stack deliberately, no random defaults |
| `sitemap` | Map every page, route, hierarchy, access level |
| `user-flows` | User journeys + request/response sequence + route maps |
| `folder-structure` | Derive/scaffold folder structure per stack |
| `design-patterns` | Classes, interactions, request flow, debugging, production readiness |
| `ssdlc` | Secure SDLC: threat modeling, auth/authz, secrets, gates per phase |
| `design-basics` | UI/UX fundamentals |
| `premium-design` | Premium UI polish |
| `performance_engineering` | Core Web Vitals, Lighthouse optimization |
| `ui-checklist` | Component/page completeness checklists |

## Important Rules

- Never default to a single UI library — always reference DESIGN.md
- Never use Mantine, Chakra UI, MUI, Ant Design
- Follow feature-first folder structure (Agent.md)
- Never use `npx install --force` or `npm install --force`

## AI Mobile Testing (OpenCode + Free Models)

Automated exploratory QA for all three Shodasha Flutter Android apps (`user_app_donor`, `vendor_app`, `rider_app`) runs on GitHub Actions using **OpenCode CLI** (`opencode run`) and **free `opencode/` models only** (no Anthropic/OpenAI keys or paid fallbacks).

- **Workflow:** `.github/workflows/ai-mobile-test.yml` (`workflow_dispatch`)
- **Scripts:** `tools/mobile-tester/` (`verify_free_model.py`, `run_android_agent.sh`, `screen.py`, `type.py`, `opencode.json`, `BRIEF.md`)

### 1. GitHub Actions Setup
1. Ensure GitHub Actions is enabled on the repository.
2. *(Optional)* Add QA test credentials in **Settings → Secrets and variables → Actions** so the agent can test authenticated flows against live Cloudflare Workers (`water`, `water-ops`):
   - `QA_CUSTOMER_PHONE`, `QA_CUSTOMER_PASSWORD`
   - `QA_VENDOR_CODE`
   - `QA_RIDER_PHONE`, `QA_RIDER_CODE`
   - Never add `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` — `verify_free_model.py` will fail if paid keys are present.

### 2. Triggering Tests
1. Go to **Actions → AI Mobile Testing (OpenCode) → Run workflow** (or use `gh workflow run ai-mobile-test.yml`).
2. Choose `app`: `all` (default — runs Customer, Vendor, and Rider apps on separate emulators), `donor`, `vendor`, or `rider`.

### 3. Configuring Free Primary & Fallback Models
- Leave `primary_model` and `fallback_model` blank to auto-discover and probe live `opencode/` free models via `opencode models`.
- To pin specific free models, pass `opencode/<model-id>` in `primary_model` / `fallback_model` when triggering `workflow_dispatch`. Non-`opencode/` models are rejected.

### 4. Retrieving Reports
Download the per-app artifact (`ai-qa-donor-<run_id>`, `ai-qa-vendor-<run_id>`, `ai-qa-rider-<run_id>`) from the workflow run summary. Each contains:
- `report.md` and `findings.json`
- Numbered half-res emulator screenshots (`01.png`, ...) and `ui.xml` dumps (`01.xml`, ...)
- `opencode-output.jsonl`, `opencode-stderr.log`, and `logcat.txt`

### 5. Known Limitations & Free-Tier Restrictions
- OpenCode's free `opencode/` model roster rotates and may enforce rate limits on shared GitHub-hosted runner IPs; if no free model responds, the workflow fails cleanly without falling back to paid APIs.
- Not all free models support multimodal image input; `screen.py` always prints the `uiautomator` element tree (`centre=(X,Y)`) alongside the PNG screenshot so text-only free models can still navigate.
- Tests point to live Cloudflare Workers (`SHODASHA_API_BASE`); clean up any QA test orders/accounts afterward if using real credentials.

## License

[License type]