"""Auth service — business rules ONLY (no SQL beyond repos, no FastAPI).

Owns: +91 phone validation, in-memory rate limits, device cap (SEC-F01),
refresh rotation + reuse detection (C7), suspended-session restrictions (§14.1).
Actor id/role always come from the session, never the client (H1).
"""

from __future__ import annotations

import datetime as _dt
import hashlib
import logging
import re
import threading
import time

from app.core.errors import AppError, RateLimitedError, ValidationError
from app.db import WRITE_LOCK

log = logging.getLogger(__name__)

ACCESS_TTL_MIN = 30
REFRESH_TTL_DAYS = 7
DEVICE_CAP = 3  # SEC-F01: <=3 accounts/device/30d, else review queue
DEVICE_WINDOW_DAYS = 30
RESEND_AFTER_S = 30

# Rate limits (contract §0).
OTP_START_PHONE_LIMIT = (5, 3600)  # 5/phone/hr
OTP_START_IP_LIMIT = (20, 3600)  # 20/IP/hr
OTP_VERIFY_DEVICE_LIMIT = (10, 3600)  # 10/device/hr (practical key for "5/code")
REFRESH_USER_LIMIT = (30, 3600)  # 30/user/hr
REGISTER_PHONE_LIMIT = (5, 3600)  # 5/phone/hr
REGISTER_IP_LIMIT = (20, 3600)  # 20/IP/hr
LOGIN_PHONE_LIMIT = (5, 900)  # 5 attempts/phone/15 min
LOGIN_IP_LIMIT = (100, 3600)  # 100/IP/hr: shared NAT stays usable; phone cap is the primary guard

# 028 access-code auth (spec §1-§3, §5): generalized codes table.
ACCESS_CODE_DEVICE_LIMIT = (10, 3600)  # 10/device/hr (mirrors DEMO pattern)
ABSOLUTE_SESSION_DAYS = 30  # spec B3: day 30 forces re-login, no sliding extension

# Server-generated OTP codes (Fast2SMS slice, ssdlc: short, few attempts).
OTP_CODE_LEN = 6
OTP_TTL_MIN = 5
OTP_MAX_ATTEMPTS = 5


class DeviceCapError(AppError):
    code = "DEVICE_CAP"
    status_code = 409


class RoleReservedError(AppError):
    code = "ROLE_RESERVED"
    status_code = 422


class AccountExistsError(AppError):
    code = "ACCOUNT_EXISTS"
    status_code = 409


class PhoneTakenError(AppError):
    code = "PHONE_TAKEN"
    status_code = 409


class OtpRetiredError(AppError):
    code = "OTP_RETIRED"
    status_code = 410


PHONE_RE = re.compile(r"[6-9]\d{9}")
LANG_RE = re.compile(r"^[a-z]{2}(-[A-Z]{2})?$")
EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$")
PASSWORD_MIN_CHARS = 8
PASSWORD_MAX_CHARS = 128


def normalize_phone(raw: str) -> str:
    """Accept +91 / 91 / 0 prefixes and separators -> +91XXXXXXXXXX."""
    digits = re.sub(r"[^\d]", "", (raw or "").strip())
    if digits.startswith("91") and len(digits) == 12:
        digits = digits[2:]
    elif digits.startswith("0") and len(digits) == 11:
        digits = digits[1:]
    if not PHONE_RE.fullmatch(digits or ""):
        raise ValidationError("Enter a valid 10-digit mobile number.", {"phone": raw})
    return "+91" + digits


def normalize_email(raw: str | None) -> str:
    """Optional email: empty is allowed; otherwise a simple RFC-lite address."""
    clean = (raw or "").strip().lower()
    if not clean:
        return ""
    if len(clean) > 254 or not EMAIL_RE.fullmatch(clean):
        raise ValidationError("Enter a valid email address.", {"email": "invalid"})
    return clean


def validate_password(raw: str | None) -> str:
    """8–128 chars, at least one letter and one digit; never trim."""
    password = raw or ""
    if (
        len(password) < PASSWORD_MIN_CHARS
        or len(password) > PASSWORD_MAX_CHARS
        or not any(ch.isalpha() for ch in password)
        or not any(ch.isdigit() for ch in password)
    ):
        raise ValidationError(
            "Password must be 8–128 characters with at least one letter and one number.",
            {"password": "invalid"},
        )
    return password


def mask_phone(phone: str) -> str:
    return "+91******" + phone[-4:]


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def DEV_AUTH_ENABLED() -> bool:
    """Reads the DEV_AUTH flag lazily (real env > .env > default) so tests and
    local runs control it per-process without import-order surprises."""
    import os  # noqa: PLC0415

    direct = os.environ.get("DEV_AUTH")
    if direct not in (None, ""):
        return direct == "1"
    try:
        from app.core.config import Settings  # noqa: PLC0415

        return bool(Settings().dev_auth)
    except Exception:
        return False


def restrictions_for(user: dict) -> dict | None:
    """Suspended sessions read + pay-dues/appeal (user) or notice-only (vendor)."""
    if not user.get("suspended"):
        return None
    if user.get("role") == "vendor":
        return {"suspended": True, "allowed": ["notice"]}
    return {
        "suspended": True,
        "allowed": ["read", "pay-dues", "appeal"],
        "reason": user.get("suspended_reason"),
    }


def integrity_status(device: dict | None) -> str:
    """Play Integrity is LOG-ONLY in slice-2: never block auth.

    Future enforce mode is a config-flag stub: when INTEGRITY_ENFORCE lands,
    reject verdicts != "pass" here with 403 instead of returning "not-verified".
    """
    verdict = (device or {}).get("integrity") or "not-verified"
    log.info("integrity device=%s verdict=%s", (device or {}).get("id"), verdict)
    return verdict


class RateLimiter:
    """Sliding-window limiter (L1 fast-path per isolate).

    Phase 8 §8.4: D1 (rate_counters, migration 019) is the cross-isolate
    source of truth — see AuthService._limit_check. This dict stays as the
    instant per-isolate deny so a D1 outage never weakens enforcement.
    """

    def __init__(self) -> None:
        self._hits: dict[str, list[float]] = {}
        self._lock = threading.Lock()

    def check(self, key: str, limit: int, window_s: int) -> None:
        now = time.monotonic()
        with self._lock:
            hits = [t for t in self._hits.get(key, []) if t > now - window_s]
            if len(hits) >= limit:
                retry = int(max(1, window_s - (now - hits[0])))
                log.warning("rate_limit l1_hit key=%s limit=%d retry_after_s=%d", key, limit, retry)
                raise RateLimitedError("Too many requests.", {"retry_after_s": retry})
            hits.append(now)
            self._hits[key] = hits

    def reset(self) -> None:  # tests only
        with self._lock:
            self._hits.clear()


_LIMITER = RateLimiter()


def reset_rate_limits() -> None:  # tests only
    _LIMITER.reset()


from app.core.db_utils import table_exists as _table_exists, write_audit  # noqa: F401
from app.core.time_utils import is_expired as _expired, utc_now as _now  # noqa: F401



def _backfill_cap(created_at: str | None, refresh_expires_at: str) -> str | None:
    """Pre-014 rows: cap = min(refresh_expires_at, created_at + 30d)."""
    try:
        refresh_dt = _dt.datetime.fromisoformat(refresh_expires_at)
        if refresh_dt.tzinfo is None:
            refresh_dt = refresh_dt.replace(tzinfo=_dt.timezone.utc)
    except (ValueError, TypeError):
        return None
    if not created_at:
        return refresh_dt.isoformat()
    try:
        created_dt = _dt.datetime.fromisoformat(created_at)
        if created_dt.tzinfo is None:
            created_dt = created_dt.replace(tzinfo=_dt.timezone.utc)
    except (ValueError, TypeError):
        return refresh_dt.isoformat()
    cap = min(refresh_dt, created_dt + _dt.timedelta(days=ABSOLUTE_SESSION_DAYS))
    return cap.isoformat()


async def _audit_access_use(conn, user_id: str, code_id: str, legacy: bool) -> None:
    """Best-effort access.use audit — never breaks the login."""
    try:  # audit must never break the login
        
        entity = "vendor_access_codes" if legacy else "access_codes"
        action = "vendor.access.use" if legacy else "access.use"
        with WRITE_LOCK:
            await write_audit(
                conn, actor=user_id, action=action,
                entity=entity, entity_id=code_id,
            )
            conn.commit()
    except Exception:  # noqa: BLE001
        try:
            conn.rollback()
        except Exception:  # noqa: BLE001
            pass
        log.warning("access.use audit failed")


def _public_user(user: dict) -> dict:
    return {
        "id": user["id"],
        "phone": user["phone"],
        "name": user.get("name"),
        "role": user["role"],
        "language": user.get("language", "hi"),
        "suspended": bool(user.get("suspended")),
        "email": user.get("email") or "",
        "assigned_vendor_id": user.get("assigned_vendor_id") or "",
    }



async def _count(conn, table: str, col: str, user_id: str) -> int:
    if not await _table_exists(conn, table):
        return 0  # slice-2: addresses table lands in 003 (may be absent)
    row = (
        await conn.execute(
            f"SELECT COUNT(*) c FROM {table} WHERE {col} = ?", (user_id,)  # noqa: S608
        )
    ).fetchone()
    return int(row["c"])


async def _ledger(conn, user_id: str) -> dict:
    if not await _table_exists(conn, "ledger"):
        return {"held": 0, "deposit_paid": 0, "deposit_refunded": 0, "dues": 0}
    row = (
        await conn.execute(
            "SELECT held, deposit_paid, deposit_refunded, dues FROM ledger WHERE customer_id = ?",
            (user_id,),
        )
    ).fetchone()
    if row is None:
        return {"held": 0, "deposit_paid": 0, "deposit_refunded": 0, "dues": 0}
    return dict(row)


async def _delete_device_token(conn, user_id: str, device_id: str) -> None:
    """Logout deletes only that device's FCM token (C8) — guarded for 002-only DBs."""
    try:
        if not await _table_exists(conn, "device_tokens"):
            return
        with WRITE_LOCK:
            await conn.execute(
                "DELETE FROM device_tokens WHERE user_id = ? AND device_id = ?",
                (user_id, device_id),
            )
            conn.commit()
    except Exception as e:  # logout must succeed even if push cleanup fails
        log.warning("device token cleanup failed: %s", e)
