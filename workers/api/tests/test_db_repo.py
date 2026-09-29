"""Slice-1 repo tests: defaults seeding, get/set roundtrip, audit, injection safety."""

import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.db import get_connection, init_schema  # noqa: E402
from app.repositories import ConfigRepo  # noqa: E402


def _repo() -> ConfigRepo:
    conn = get_connection(":memory:")
    init_schema(conn)
    return ConfigRepo(conn)


def test_connection_uses_row_factory():
    conn = get_connection(":memory:")
    assert conn.row_factory is sqlite3.Row
    conn.close()


def test_seed_defaults():
    assert _repo().all_rates() == {"refill": 2800, "container": 3000, "deposit": 15000, "cap": 300}


def test_seed_defaults_match_settings():
    try:
        from app.core.config import Settings
    except ImportError:
        return  # B1 deps not installed here; fallback constants cover it
    fields = Settings.model_fields
    assert _repo().all_rates() == {
        "refill": fields["rate_refill_paise"].default,
        "container": fields["rate_container_paise"].default,
        "deposit": fields["deposit_per_jar_paise"].default,
        "cap": fields["cap_charge_paise"].default,
    }


def test_get_set_roundtrip():
    repo = _repo()
    repo.all_rates()  # seeds defaults on first use
    assert repo.get("refill") == "2800"
    assert repo.get("missing", "fallback") == "fallback"
    repo.set("refill", "3500", updated_by="admin")
    assert repo.get("refill") == "3500"
    assert repo.all_rates()["refill"] == 3500


def test_set_writes_audit_row():
    repo = _repo()
    repo.set("deposit", "200", updated_by="admin")
    row = repo._conn.execute(
        "SELECT actor, action, entity, entity_id FROM audit_log WHERE entity_id = ?",
        ("deposit",),
    ).fetchone()
    assert (row["actor"], row["action"], row["entity"], row["entity_id"]) == (
        "admin",
        "config.set",
        "config",
        "deposit",
    )


def test_sql_injection_attempt_stored_harmlessly():
    repo = _repo()
    evil = "x'; DROP TABLE config;--"
    repo.set(evil, "1", updated_by="admin")
    assert repo.get(evil) == "1"
    # Table intact + seed data still queryable.
    assert repo.all_rates()["refill"] == 2800
