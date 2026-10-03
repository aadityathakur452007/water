"""FCM sender (Adapter pattern) — push-only, server-targeted (contract §4.10).

FakeFcm records sends in-memory for tests. RealFcm is a skeleton over the
FCM v1 HTTP API using the SAME Firebase service account as auth (needs the
project id + OAuth2 access token wiring); it raises StubError until wired so
nobody mistakes it for working code. notify() is best-effort: it NEVER raises
to callers — push must not break order/complaint flows.
"""

from __future__ import annotations

import logging
from typing import Protocol

log = logging.getLogger(__name__)


class StubError(Exception):
    """RealFcm used before the Firebase service-account wiring lands."""


class FcmSender(Protocol):
    def send(self, token: str, title: str, body: str, data: dict | None = None) -> str:
        """Send one push; return the provider message id."""
        ...  # pragma: no cover


class FakeFcm:
    """In-memory sender for tests: records every send, never touches network."""

    def __init__(self):
        self.sent: list[dict] = []

    def send(self, token: str, title: str, body: str, data: dict | None = None) -> str:
        mid = f"fake-{len(self.sent) + 1}"
        self.sent.append({"token": token, "title": title, "body": body,
                          "data": data or {}, "id": mid})
        return mid


class RealFcm:
    """FCM v1 skeleton — raises StubError until wired to the service account."""

    def __init__(self, project_id: str | None = None, access_token: str | None = None):
        self.project_id = project_id
        self.access_token = access_token

    def send(self, token: str, title: str, body: str, data: dict | None = None) -> str:
        raise StubError(
            "FCM not wired: needs the Firebase service-account (same project as auth)"
            " + OAuth2 access token for the FCM v1 API."
        )


def notify(sender: FcmSender | None, token: str, title: str, body: str,
           data: dict | None = None) -> bool:
    """Best-effort push. Returns True on send, False on any failure. Never raises."""
    if sender is None or not token:
        return False
    try:
        sender.send(token, title, body, data or {})
    except Exception as e:  # noqa: BLE001 — push is fire-and-forget by design
        log.warning("fcm notify failed (best-effort): %s", e)
        return False
    return True


async def queue_or_log(conn, user_id: str, kind: str, message: str,
                       channels: list[str] | None = None) -> bool:
    """Durable outbox ONLY if an outbox table exists, else structured log.

    Never sends a real push, needs no secrets, creates no tables (a future
    migration owns the schema; unknown schemas fall back to log). Never
    raises. Returns True if a row was queued.
    """
    try:
        tables = {r["name"] for r in (await conn.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table'")).fetchall()}
    except Exception as e:  # noqa: BLE001 — queueing is best-effort
        log.info("fcm outbox check failed user=%s kind=%s err=%s", user_id, kind, e)
        return False
    target = ("notification_outbox" if "notification_outbox" in tables
              else ("outbox" if "outbox" in tables else None))
    if target is None:
        log.info("fcm reminder user=%s kind=%s channels=%s msg=%s",
                 user_id, kind, ",".join(channels or ["fcm"]), message)
        return False
    try:
        cols = {r["name"] for r in (await conn.execute(f"PRAGMA table_info({target})")).fetchall()}
        if {"user_id", "kind", "message"} <= cols:
            import datetime as _dt
            import uuid as _uuid

            await conn.execute(
                f"INSERT INTO {target}(id, user_id, kind, message, created_at)"
                " VALUES (?, ?, ?, ?, ?)",
                (_uuid.uuid4().hex, user_id, kind, message,
                 _dt.datetime.now(_dt.timezone.utc).isoformat()),
            )
            conn.commit()
            return True
        log.info("fcm outbox schema-mismatch user=%s kind=%s msg=%s", user_id, kind, message)
    except Exception as e:  # noqa: BLE001 — queueing is best-effort
        log.info("fcm outbox queue failed user=%s kind=%s err=%s", user_id, kind, e)
    return False
