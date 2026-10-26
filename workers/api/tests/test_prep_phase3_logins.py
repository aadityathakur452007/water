"""Tests for scripts/prep_phase3_logins.py. No network, no D1, no real credentials."""

from __future__ import annotations

import asyncio
import json
import sqlite3
import sys
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = API_ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import prep_phase3_logins as prep  # noqa: E402
from app.core.passwords import verify_password  # noqa: E402

NOW = "2026-10-26T00:00:00+00:00"
USERS_SCHEMA = """
CREATE TABLE users (
    id TEXT PRIMARY KEY,
    phone TEXT UNIQUE,
    firebase_uid TEXT UNIQUE,
    name TEXT,
    role TEXT NOT NULL DEFAULT 'user',
    language TEXT NOT NULL DEFAULT 'hi',
    kyc_status TEXT NOT NULL DEFAULT 'none',
    suspended INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    email TEXT NOT NULL DEFAULT '',
    password_hash TEXT,
    password_updated_at TEXT
);
"""


def _build(count: int = 3, run_id: str = "testrun1") -> list[prep.LoginUser]:
    return asyncio.run(prep.build_users(count, run_id, NOW))


def test_hashes_verify_and_repr_hides_secrets() -> None:
    users = _build()

    for user in users:
        assert asyncio.run(verify_password(user.password, user.password_hash))
        assert not asyncio.run(verify_password(user.password + "x", user.password_hash))

    rendered = repr(users)
    for user in users:
        assert user.password not in rendered
        assert user.password_hash not in rendered


def test_ids_and_phones_are_unique_and_well_formed() -> None:
    users = _build(90)

    assert len({user.id for user in users}) == 90
    assert len({user.phone for user in users}) == 90
    assert [user.id for user in users] == [
        f"load3-login-testrun1-{n:03d}" for n in range(1, 91)
    ]
    assert all(prep.PHONE_RE.fullmatch(user.phone) for user in users)


def test_sql_contains_only_user_inserts_and_no_plaintext() -> None:
    users = _build()
    sql = prep.render_sql(users)

    body = "\n".join(
        line for line in sql.splitlines() if not line.lstrip().startswith("--")
    )
    statements = [part.strip() for part in body.split(";") if part.strip()]
    assert len(statements) == len(users)
    assert all(statement.startswith("INSERT INTO users ") for statement in statements)

    for user in users:
        assert user.password not in sql
        assert user.password_hash in sql
        assert user.phone in sql


def test_sql_applies_and_stores_the_matching_hash() -> None:
    users = _build()
    connection = sqlite3.connect(":memory:")
    connection.executescript(USERS_SCHEMA)
    connection.executescript(prep.render_sql(users))

    rows = connection.execute(
        "SELECT id, phone, password_hash FROM users ORDER BY id"
    ).fetchall()
    assert len(rows) == len(users)

    by_phone = {user.phone: user for user in users}
    for user_id, phone, password_hash in rows:
        user = by_phone[phone]
        assert user.id == user_id
        assert asyncio.run(verify_password(user.password, password_hash))


def test_write_outputs_emits_harness_credentials_shape(tmp_path: Path) -> None:
    users = _build()
    sql_path = tmp_path / "phase3-logins.sql"
    credentials_path = tmp_path / "phase3-login-credentials.json"

    prep.write_outputs(sql_path, credentials_path, users)

    payload = json.loads(credentials_path.read_text(encoding="utf-8"))
    assert len(payload) == len(users)
    assert all(set(item) == {"phone", "password"} for item in payload)
    assert [item["phone"] for item in payload] == [user.phone for user in users]
    assert [item["password"] for item in payload] == [user.password for user in users]
    assert sql_path.read_text(encoding="utf-8") == prep.render_sql(users)


def test_outputs_must_stay_outside_the_repository(tmp_path: Path) -> None:
    prep.ensure_outside_repo(tmp_path / "ok.json", "credentials")

    with pytest.raises(SystemExit):
        prep.ensure_outside_repo(API_ROOT / "data" / "leak.json", "credentials")


@pytest.mark.parametrize("count,run_id", [(0, "testrun1"), (1, "BAD!")])
def test_invalid_inputs_are_rejected(count: int, run_id: str) -> None:
    with pytest.raises(ValueError):
        asyncio.run(prep.build_users(count, run_id, NOW))
