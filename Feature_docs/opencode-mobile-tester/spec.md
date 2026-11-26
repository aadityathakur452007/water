# Feature Spec: OpenCode AI Mobile Testing Pipeline

## 1. Objective
Integrate a fully automated, zero-cost AI mobile QA testing pipeline into `Water` using **OpenCode CLI (`opencode run`)** and **OpenCode's native free models** on GitHub Actions (`ubuntu-latest`) for all three Shodasha Flutter Android apps (`user_app_donor`, `vendor_app`, `rider_app`) pointing to live Cloudflare Workers.

## 2. Requirements
- **Zero paid AI APIs:** No Anthropic/Claude API, no OpenAI API, no paid model fallback. Fail clearly if no free `opencode/` model is available.
- **Dynamic free-model discovery:** Never hardcode unverified model names. Query `opencode models` at runtime, filter to free `opencode/` models, probe with a real `opencode run` prompt, and select primary + fallback.
- **All 3 Flutter apps tested separately:** Matrix job on `workflow_dispatch` (`app`: `all` [default], `donor`, `vendor`, `rider`), each with its own Android emulator, APK build (JDK 21 + Flutter 3.44.9 + live `SHODASHA_API_BASE`), and OpenCode agent.
- **Real emulator interaction:** Screenshots (`screencap`), UI hierarchy (`uiautomator dump`), tap, swipe, back, text input, and `logcat` crash capture.
- **Artifacts:** Upload screenshots, OpenCode JSONL logs, `logcat.txt`, `report.md`, and `findings.json` per app.

## 3. Architecture & Files
- `tools/mobile-tester/opencode.json` — OpenCode config pinning free `opencode` provider and tool permissions.
- `tools/mobile-tester/verify_free_model.py` — Discovers, validates, and probes free `opencode/` models (strictly rejects paid providers).
- `tools/mobile-tester/screen.py` — Captures half-size PNG screenshot + `uiautomator` element centers + `logcat` crash check.
- `tools/mobile-tester/type.py` — ASCII-safe `adb shell input text` helper.
- `tools/mobile-tester/BRIEF.md` — Exploratory QA instructions for Shodasha's Customer, Vendor, and Rider apps.
- `tools/mobile-tester/run_android_agent.sh` — Installs APK, launches app, runs `opencode run` with primary/fallback free model, collects logs/reports.
- `.github/workflows/ai-mobile-test.yml` — `workflow_dispatch` CI/CD pipeline.
- `tests/test_mobile_tester.py` — Unit tests for free-model verification and helper scripts.
