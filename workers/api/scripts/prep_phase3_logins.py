"""Prepare dedicated synthetic login users for the Phase 3P login probe.

Emits a D1 SQL file containing only ``INSERT INTO users`` statements plus a
temporary credentials JSON for ``bench_phase0.py --profile login``. Passwords
are generated per user, hashed with ``app.core.passwords.hash_password``
(PBKDF2-HMAC-SHA256, 100k), and never printed.

Both output paths must be outside the repository. The credentials file is the
only place a plaintext password is written.

Usage (from ``workers/api``)::

    python scripts/prep_phase3_logins.py --count 90 \
        --sql "$env:TEMP\\phase3-logins.sql" \
        --credentials "$env:TEMP\\phase3-login-credentials.json"
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import re
import secrets
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

API_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = API_ROOT.parents[1]
SRC_ROOT = API_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from app.core.passwords import hash_password  # noqa: E402

RUN_ID_RE = re.compile(r"^[a-z0-9]{4,16}$")
PHONE_RE = re.compile(r"^\+919\d{9}$")
PHONE_BLOCK_MIN = 900_000_000
PHONE_BLOCK_SPAN = 90_000_000
MAX_USERS = 500

USER_COLUMNS = (
    "id", "phone", "firebase_uid", "name", "role", "language", "kyc_status",
    "suspended", "created_at", "email", "password_hash", "password_updated_at",
)


@dataclass(frozen=True)
class LoginUser:
    id: str
    phone: str
    name: str
    created_at: str
    password: str = field(repr=False)
    password_hash: str = field(repr=False)


def make_password() -> str:
    """A synthetic password that always satisfies the login validator."""
    return f"L3-{secrets.token_urlsafe(12)}"


def phone_block(run_id: str) -> int:
    digest = hashlib.sha256(run_id.encode("utf-8")).digest()
    return PHONE_BLOCK_MIN + int.from_bytes(digest[:8], "big") % PHONE_BLOCK_SPAN


async def build_users(count: int, run_id: str, now: str | None = None) -> list[LoginUser]:
    if not 1 <= count <= MAX_USERS:
        raise ValueError(f"count must be between 1 and {MAX_USERS}")
    if not RUN_ID_RE.fullmatch(run_id):
        raise ValueError("run_id must be 4-16 lowercase letters or digits")

    created_at = now or datetime.now(timezone.utc).isoformat()
    block = phone_block(run_id)
    users: list[LoginUser] = []
    for n in range(1, count + 1):
        suffix = f"{n:03d}"
        password = make_password()
        users.append(
            LoginUser(
                id=f"load3-login-{run_id}-{suffix}",
                phone=f"+919{block + n:09d}",
                name=f"Load3 Login {run_id} {suffix}",
                created_at=created_at,
                password=password,
                password_hash=await hash_password(password),
            )
        )
    return users


def _sql_value(value: object) -> str:
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, (int, float)):
        return str(value)
    return "'" + str(value).replace("'", "''") + "'"


def render_sql(users: list[LoginUser]) -> str:
    lines = [
        "-- Phase 3P synthetic login users. Only INSERT INTO users.",
        "-- Contains password hashes; keep this file outside the repository.",
    ]
    for user in users:
        values = (
            user.id,
            user.phone,
            None,
            user.name,
            "user",
            "en",
            "none",
            False,
            user.created_at,
            f"load3-{user.id.removeprefix('load3-login-')}@example.invalid",
            user.password_hash,
            user.created_at,
        )
        rendered = ", ".join(_sql_value(value) for value in values)
        lines.append(
            f"INSERT INTO users ({', '.join(USER_COLUMNS)}) VALUES ({rendered}) "
            "ON CONFLICT (id) DO NOTHING;"
        )
    return "\n".join(lines) + "\n"


def ensure_outside_repo(path: Path, label: str) -> None:
    resolved = path.resolve()
    if resolved == REPO_ROOT or REPO_ROOT in resolved.parents:
        raise SystemExit(f"refusing to write {label} inside the repository: {resolved}")


def write_outputs(
    sql_path: Path, credentials_path: Path, users: list[LoginUser]
) -> None:
    ensure_outside_repo(sql_path, "SQL file")
    ensure_outside_repo(credentials_path, "credentials file")

    sql_path.parent.mkdir(parents=True, exist_ok=True)
    credentials_path.parent.mkdir(parents=True, exist_ok=True)
    sql_path.write_text(render_sql(users), encoding="utf-8", newline="\n")
    credentials_path.write_text(
        json.dumps(
            [{"phone": user.phone, "password": user.password} for user in users],
            indent=2,
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )
    try:
        credentials_path.chmod(0o600)
    except OSError:
        pass


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        description="Generate synthetic Phase 3P login users (D1 SQL + credentials).",
    )
    ap.add_argument("--count", type=int, default=90, help="number of users (default: 90)")
    ap.add_argument("--run-id", default=None, help="4-16 lowercase letters/digits (default: random)")
    ap.add_argument("--sql", required=True, help="D1 SQL output path (outside the repo)")
    ap.add_argument(
        "--credentials",
        required=True,
        help="credentials JSON output path (outside the repo)",
    )
    return ap.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    run_id = args.run_id or secrets.token_hex(4)
    if not RUN_ID_RE.fullmatch(run_id):
        print("run_id must be 4-16 lowercase letters or digits", file=sys.stderr)
        return 2
    if not 1 <= args.count <= MAX_USERS:
        print(f"count must be between 1 and {MAX_USERS}", file=sys.stderr)
        return 2

    sql_path = Path(args.sql)
    credentials_path = Path(args.credentials)
    for path, label in ((sql_path, "SQL"), (credentials_path, "credentials")):
        if path.exists():
            print(f"refusing to overwrite existing {label} file: {path}", file=sys.stderr)
            return 1

    users = asyncio.run(build_users(args.count, run_id))
    write_outputs(sql_path, credentials_path, users)
    print(f"prepared users={len(users)} run_id={run_id}")
    print(f"sql={sql_path.resolve()}")
    print(f"credentials={credentials_path.resolve()}")
    print("inspect the SQL, then apply it once to shodasha-staging")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
