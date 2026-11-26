"""Shared HTTP route helpers for user ID extraction and idempotency headers."""

from __future__ import annotations

from app.core.errors import ValidationError


def user_id(user: object) -> str:
    """Extract string user ID from a request user dict or object."""
    if isinstance(user, dict):
        return str(user.get("id"))
    return str(getattr(user, "id"))


def require_idempotency_key(idem: str | None) -> str:
    """Validate and return a non-empty Idempotency-Key header."""
    if not idem or not idem.strip():
        raise ValidationError(message="Idempotency-Key header required.", details={})
    return idem.strip()
