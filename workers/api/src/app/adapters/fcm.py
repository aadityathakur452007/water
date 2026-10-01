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
