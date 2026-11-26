"""Discover and verify free OpenCode models for headless CI testing.

Strictly enforces zero paid APIs:
- Rejects any non-`opencode/` model or paid provider environment keys.
- Queries `opencode models` dynamically (never hardcodes unverified names).
- Probes candidates with a real `opencode run` call to confirm availability.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from typing import Iterable

FORBIDDEN_ENV_KEYS = (
    "ANTHROPIC_API_KEY",
    "CLAUDE_CODE_OAUTH_TOKEN",
    "OPENAI_API_KEY",
    "OPENROUTER_API_KEY",
)

# Preference order when auto-selecting among discovered `opencode/` free vision models.
PREFERRED_KEYWORDS = ("deepseek", "glm", "mimo", "hy4", "longcat", "inkling", "nemotron", "flash", "free")


def _opencode_exe() -> str:
    return shutil.which("opencode") or "opencode"


def check_clean_env(env: dict[str, str] | None = None) -> None:
    """Fail if any paid provider credential is present in the environment."""
    target = env if env is not None else os.environ
    present = [k for k in FORBIDDEN_ENV_KEYS if target.get(k, "").strip()]
    if present:
        raise RuntimeError(
            f"Paid provider credentials detected ({', '.join(present)}). "
            "Remove paid keys to guarantee free-only OpenCode execution."
        )


def parse_opencode_models(raw_output: str) -> list[str]:
    """Extract unique `opencode/<model>` identifiers from `opencode models` output."""
    seen: set[str] = set()
    models: list[str] = []
    for line in raw_output.splitlines():
        match = re.search(r"\b(opencode/[A-Za-z0-9._:-]+)\b", line.strip())
        if match:
            model_id = match.group(1)
            if model_id not in seen:
                seen.add(model_id)
                models.append(model_id)
    return models


def is_allowed_free_model_id(model_id: str) -> bool:
    """Only native `opencode/` models are eligible (never `anthropic/`, `openai/`, etc.)."""
    return bool(model_id and model_id.startswith("opencode/"))


def rank_candidates(
    discovered: Iterable[str],
    primary_override: str = "",
    fallback_override: str = "",
) -> list[str]:
    """Order candidate models: explicit overrides first, then preferred free models."""
    ordered: list[str] = []
    for override in (primary_override.strip(), fallback_override.strip()):
        if not override:
            continue
        if not is_allowed_free_model_id(override):
            raise ValueError(
                f"Rejected model '{override}': only native 'opencode/<model>' free models are allowed."
            )
        if override not in ordered:
            ordered.append(override)

    def score(m: str) -> tuple[int, str]:
        lower = m.lower()
        for idx, kw in enumerate(PREFERRED_KEYWORDS):
            if kw in lower:
                return (idx, m)
        return (len(PREFERRED_KEYWORDS), m)

    for m in sorted(discovered, key=score):
        if is_allowed_free_model_id(m) and m not in ordered:
            ordered.append(m)
    return ordered


def parse_verbose_free_vision_models(raw_output: str) -> tuple[list[str], list[str]]:
    """Parse `opencode models opencode --verbose` into (free_vision_models, free_text_models)."""
    lines = raw_output.splitlines()
    vision: list[str] = []
    text_only: list[str] = []
    i = 0
    while i < len(lines):
        if lines[i].startswith("opencode/"):
            mid = lines[i].strip()
            j = i + 1
            buf: list[str] = []
            while j < len(lines) and not lines[j].startswith("opencode/"):
                buf.append(lines[j])
                j += 1
            try:
                data = json.loads("\n".join(buf))
                cost = data.get("cost", {})
                caps = data.get("capabilities", {})
                if cost.get("input", 1) == 0 and cost.get("output", 1) == 0 and caps.get("toolcall"):
                    if caps.get("input", {}).get("image"):
                        vision.append(mid)
                    else:
                        text_only.append(mid)
            except json.JSONDecodeError:
                pass
            i = j
        else:
            i += 1
    return vision, text_only


def discover_models() -> list[str]:
    """Run `opencode models opencode --verbose` and return free `opencode/` models (vision-first)."""
    exe = _opencode_exe()
    proc = subprocess.run(
        [exe, "models", "opencode", "--verbose"],
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=60,
        check=False,
    )
    if proc.returncode == 0:
        vision, text_only = parse_verbose_free_vision_models(proc.stdout)
        if vision:
            return vision
        if text_only:
            return text_only

    # Fallback to plain `opencode models` if --verbose format changes
    proc = subprocess.run(
        [exe, "models"],
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=60,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"`opencode models` failed (exit {proc.returncode}): {proc.stderr.strip()}")
    models = parse_opencode_models(proc.stdout)
    if not models:
        raise RuntimeError(
            "No `opencode/` models found in `opencode models` output:\n" + proc.stdout[:500]
        )
    return models


def probe_model(model_id: str, timeout_s: int = 35) -> tuple[bool, str]:
    """Execute a real headless `opencode run` prompt to verify the model is free & responsive."""
    try:
        proc = subprocess.run(
            [_opencode_exe(), "run", "--format", "json", "--model", model_id, "--", "Reply with exactly: OK"],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=timeout_s,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return False, f"Timed out after {timeout_s}s"
    except OSError as exc:
        return False, f"Execution error: {exc}"
    combined = f"{proc.stdout}\n{proc.stderr}".strip()
    if proc.returncode != 0:
        return False, combined[-400:]
    if not proc.stdout.strip():
        return False, "Empty stdout from opencode run"
    # Verify JSONL output contains at least one valid JSON event without an auth/billing error
    lower = combined.lower()
    if any(err in lower for err in ("insufficient_quota", "payment required", "billing", "api key")):
        return False, combined[-400:]
    return True, "OK"


def main() -> int:
    check_clean_env()
    primary_override = os.environ.get("PRIMARY_MODEL", "").strip()
    fallback_override = os.environ.get("FALLBACK_MODEL", "").strip()

    discovered = discover_models()
    candidates = rank_candidates(discovered, primary_override, fallback_override)
    print(f"Discovered {len(discovered)} opencode/ models; probing up to {min(len(candidates), 6)}...")

    verified: list[str] = []
    for candidate in candidates[:6]:
        ok, detail = probe_model(candidate)
        status = "PASS" if ok else f"FAIL ({detail})"
        print(f"  - {candidate}: {status}")
        if ok:
            verified.append(candidate)
            if len(verified) >= 2:
                break

    if not verified:
        print("ERROR: No working free opencode/ model is currently available.", file=sys.stderr)
        return 1

    primary = verified[0]
    fallback = verified[1] if len(verified) > 1 else ""
    print(f"Selected primary={primary}, fallback={fallback or 'none'}")

    gh_out = os.environ.get("GITHUB_OUTPUT")
    if gh_out:
        with open(gh_out, "a", encoding="utf-8") as f:
            f.write(f"primary_model={primary}\n")
            f.write(f"fallback_model={fallback}\n")

    print(json.dumps({"primary_model": primary, "fallback_model": fallback}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
