"""Worker env bridge tests (app.core.worker_env).

Proves request-scoped vars win on Workers while local/pytest behavior is
unchanged — and that the DEV_AUTH backdoor can never be armed from the
worker env (it reads os.environ only, which is empty in production).
"""

import os
import sys
from pathlib import Path

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.core.worker_env import env_get, set_worker_env  # noqa: E402
from app.services.auth_service import DEV_AUTH_ENABLED  # noqa: E402


class _FakeEnv:
    def __init__(self, **kv):
        self.__dict__.update(kv)


def test_local_falls_back_to_os_environ(monkeypatch):
    set_worker_env(None)
    monkeypatch.setenv("SHODASHA_PROBE_KEY", "from-os")
    assert env_get("SHODASHA_PROBE_KEY") == "from-os"
    assert env_get("SHODASHA_PROBE_MISSING") is None
    assert env_get("SHODASHA_PROBE_MISSING", "dflt") == "dflt"


def test_worker_env_wins_over_os_environ(monkeypatch):
    monkeypatch.setenv("SHODASHA_PROBE_KEY", "from-os")
    set_worker_env(_FakeEnv(SHODASHA_PROBE_KEY="from-worker"))
    try:
        assert env_get("SHODASHA_PROBE_KEY") == "from-worker"
    finally:
        set_worker_env(None)


def test_dev_auth_ignores_worker_env(monkeypatch):
    """Even a malicious/buggy worker var cannot change the dev backdoor.

    DEV_AUTH_ENABLED reads os.environ + the local .env file only — the
    request worker env is never consulted, so the backdoor stays dead in
    production regardless of worker vars.
    """
    monkeypatch.delenv("DEV_AUTH", raising=False)
    baseline = DEV_AUTH_ENABLED()
    set_worker_env(_FakeEnv(DEV_AUTH="1" if not baseline else "0"))
    try:
        assert DEV_AUTH_ENABLED() is baseline
    finally:
        set_worker_env(None)


def test_firebase_verifier_reads_worker_env(monkeypatch):
    from app.adapters import firebase

    monkeypatch.delenv("FIREBASE_PROJECT_ID", raising=False)
    set_worker_env(_FakeEnv(FIREBASE_PROJECT_ID="worker-proj"))
    try:
        assert firebase.RealVerifier().project_id == "worker-proj"
    finally:
        set_worker_env(None)
