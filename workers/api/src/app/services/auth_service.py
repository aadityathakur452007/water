"""Auth service — business rules ONLY (no SQL beyond repos, no FastAPI).

Owns: +91 phone validation, in-memory rate limits, device cap (SEC-F01),
refresh rotation + reuse detection (C7), suspended-session restrictions (§14.1).
Actor id/role always come from the session, never the client (H1).
"""

from __future__ import annotations

import datetime as _dt
import hashlib
import hmac
import logging
import re
import secrets
import threading
import time
import uuid

from app.adapters.firebase import UnauthError
from app.core.errors import AppError, NotFoundError, RateLimitedError, ValidationError
from app.db import WRITE_LOCK
from app.repositories.session_repo import SessionRepo
from app.repositories.user_repo import UserRepo

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

# Server-generated OTP codes (Fast2SMS slice, ssdlc: short, few attempts).
OTP_CODE_LEN = 6
OTP_TTL_MIN = 5
OTP_MAX_ATTEMPTS = 5


class DeviceCapError(AppError):
    code = "DEVICE_CAP"
    status_code = 409


PHONE_RE = re.compile(r"[6-9]\d{9}")
LANG_RE = re.compile(r"^[a-z]{2}(-[A-Z]{2})?$")


def normalize_phone(raw: str) -> str:
    """Accept +91XXXXXXXXXX / 91XXXXXXXXXX / XXXXXXXXXX -> +91XXXXXXXXXX."""
    digits = re.sub(r"[^\d]", "", (raw or "").strip())
    if digits.startswith("91") and len(digits) == 12:
        digits = digits[2:]
    if not PHONE_RE.fullmatch(digits or ""):
        raise ValidationError("Enter a valid 10-digit mobile number.", {"phone": raw})
    return "+91" + digits


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
    """Sliding-window limiter."""

    # TODO slice-3: D1-backed counters (multi-isolate). This dict is slice-2-local:
    # each Worker isolate counts on its own, so global limits are approximate.
    def __init__(self) -> None:
        self._hits: dict[str, list[float]] = {}
        self._lock = threading.Lock()

    def check(self, key: str, limit: int, window_s: int) -> None:
        now = time.monotonic()
        with self._lock:
            hits = [t for t in self._hits.get(key, []) if t > now - window_s]
            if len(hits) >= limit:
                retry = int(max(1, window_s - (now - hits[0])))
                raise RateLimitedError("Too many requests.", {"retry_after_s": retry})
            hits.append(now)
            self._hits[key] = hits

    def reset(self) -> None:  # tests only
        with self._lock:
            self._hits.clear()


_LIMITER = RateLimiter()


def reset_rate_limits() -> None:  # tests only
    _LIMITER.reset()


def _now() -> _dt.datetime:
    return _dt.datetime.now(_dt.timezone.utc)


class AuthService:
    """Session mint/refresh/logout + profile (constructor injection for tests)."""

    def __init__(self, conn, verifier=None):
        self._conn = conn
        self._users = UserRepo(conn)
        self._sessions = SessionRepo(conn)
        self._verifier = verifier  # duck-typed verify_id_token(); None = only local ops

    # -- OTP ---------------------------------------------------------------

    async def otp_start(self, phone: str, ip: str) -> dict:
        phone = normalize_phone(phone)
        _LIMITER.check(f"otp-start:phone:{phone}", *OTP_START_PHONE_LIMIT)
        _LIMITER.check(f"otp-start:ip:{ip or 'unknown'}", *OTP_START_IP_LIMIT)
        # firebase (default): Firebase sends the SMS client-side; the server
        # only gates abuse (SEC-A02). fast2sms/textbee: the server mints a
        # single-use code, stores only its hash, and sends it via the provider
        # (Fast2SMS DLT route, or the user's own phone over TextBee — no DLT).
        from app.adapters.sms import get_sms_provider, otp_provider  # noqa: PLC0415 (lazy seam)

        if otp_provider() in ("fast2sms", "textbee"):
            from app.repositories.otp_repo import OtpRepo  # noqa: PLC0415 (lazy seam)

            code = "".join(secrets.choice("0123456789") for _ in range(OTP_CODE_LEN))
            await OtpRepo(self._conn).issue(phone=phone, code_hash=hash_token(code), ttl_min=OTP_TTL_MIN)
            get_sms_provider().send_otp(phone, code)
            return {
                "sent_to_masked": mask_phone(phone),
                "resend_after_s": RESEND_AFTER_S,
                "channel": "sms",
            }
        return {
            "sent_to_masked": mask_phone(phone),
            "resend_after_s": RESEND_AFTER_S,
            "channel": "firebase",
        }

    async def otp_verify(
        self, id_token: str | None, device: dict, phone: str | None = None, code: str | None = None
    ) -> dict:
        device_id = (device or {}).get("id") or ""
        if not device_id.strip():
            raise ValidationError("Device id required.", {"device": "id"})
        _LIMITER.check(f"otp-verify:device:{device_id}", *OTP_VERIFY_DEVICE_LIMIT)
        # Server-code path (fast2sms): phone + 6-digit code, no Firebase round-trip.
        if code:
            from app.repositories.otp_repo import OtpRepo  # noqa: PLC0415 (lazy seam)

            phone_n = normalize_phone(phone or "")
            outcome = await OtpRepo(self._conn).consume(
                phone=phone_n, code_hash=hash_token(code.strip()), max_attempts=OTP_MAX_ATTEMPTS
            )
            if outcome == "expired":
                raise ValidationError("Code expired. Please resend.", {"otp_code": "expired"})
            if outcome == "locked":
                raise RateLimitedError("Too many wrong attempts. Resend a new code.", {})
            if outcome != "ok":
                raise ValidationError("Wrong code. Try again.", {"otp_code": "mismatch"})
            user = await self._users.upsert_phone_user(phone=phone_n)
            return await self._issue_session(user, device_id, device)
        # DEV_AUTH=1 (local dev only): a raw code of `dev|<phone>|<any>` logs the
        # EXISTING account for that phone in, with no Firebase round-trip. The
        # admin web sends this format when its dev fallback is on. Never enable
        # in production: it bypasses the SMS OTP entirely.
        if (id_token or "").startswith("dev|") and DEV_AUTH_ENABLED():
            parts = (id_token or "").split("|", 2)  # "dev|<phone>|<any>"
            if len(parts) != 3:
                raise UnauthError("Invalid session.", {})
            phone = normalize_phone(parts[1])
            user = await self._users.find_by_phone(phone)
            if user is None:
                raise UnauthError("No account for this phone. Seed it first.", {})
            return await self._issue_session(user, device_id)
        if self._verifier is None or not id_token:
            raise UnauthError("Invalid session.", {})
        claims = self._verifier.verify_id_token(id_token)
        if not claims.get("uid"):
            raise UnauthError("Invalid session.", {})
        if not claims.get("phone_number"):
            # Google/email sign-ins carry no phone claim; v1 accounts are phone-keyed.
            # Phone-link flow ships in a later phase — fail loudly, never mint phoneless.
            raise ValidationError(
                "This login has no phone number. Please sign in with phone OTP.",
                {"id_token": "phone_number missing"},
            )
        phone = normalize_phone(claims.get("phone_number") or "")
        user = await self._users.upsert_firebase_user(phone=phone, firebase_uid=str(claims["uid"]))
        return await self._issue_session(user, device_id, device)

    # -- demo login (QA only) ------------------------------------------------
    # Config-gated OTP bypass for demo accounts: no SMS round-trip, the app
    # signs in with a seeded phone + demo code. The gate is the `config`
    # table (`demo_login_enabled` = 1) PLUS a matching row in `demo_codes`
    # (hash-only, revocable per phone). Prod stays closed by keeping the
    # flag 0 and the table empty; the seed script turns it on explicitly.
    DEMO_LOGIN_DEVICE_LIMIT = (10, 3600)  # same shape as OTP verify abuse cap

    async def demo_login(
        self, phone: str | None, code: str | None, device_id: str, device: dict | None = None
    ) -> dict:
        from app.repositories.config_repo import ConfigRepo  # noqa: PLC0415 (lazy seam)

        if not (device_id or "").strip():
            raise ValidationError("Device id required.", {"device": "id"})
        flag = await ConfigRepo(self._conn).get("demo_login_enabled", "0")
        if (flag or "0").strip() != "1":
            raise UnauthError("Demo login is off.", {})
        _LIMITER.check(f"demo-login:device:{device_id}", *self.DEMO_LOGIN_DEVICE_LIMIT)
        phone_n = normalize_phone(phone or "")
        row = (
            await self._conn.execute(
                "SELECT code_hash FROM demo_codes WHERE phone = ?", (phone_n,)
            )
        ).fetchone()
        want = hash_token((code or "").strip())
        if row is None or not hmac.compare_digest(str(row["code_hash"]), want):
            raise UnauthError("Invalid demo credentials.", {})
        user = await self._users.find_by_phone(phone_n)
        if user is None:
            raise UnauthError("No account for this phone. Seed it first.", {})
        return await self._issue_session(user, device_id, device)

    async def _issue_session(self, user: dict, device_id: str, device: dict | None = None) -> dict:
        """Session minting shared by the Firebase path and the DEV_AUTH path."""
        since = (_now() - _dt.timedelta(days=DEVICE_WINDOW_DAYS)).isoformat()
        bound = await self._sessions.device_user_ids(device_id, since)
        if user["id"] not in bound and len(bound) >= DEVICE_CAP:
            raise DeviceCapError(
                "Too many accounts on this device. Contact support.",
                {"device_id": device_id},
            )
        new_device = not await self._sessions.known_device(user["id"], device_id)
        access, refresh = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
        row = await self._sessions.create(
            user_id=user["id"],
            role=user["role"],
            device_fp=device_id,
            access_hash=hash_token(access),
            refresh_hash=hash_token(refresh),
            family_id=uuid.uuid4().hex,
            expires_at=(_now() + _dt.timedelta(minutes=ACCESS_TTL_MIN)).isoformat(),
            refresh_expires_at=(_now() + _dt.timedelta(days=REFRESH_TTL_DAYS)).isoformat(),
            created_at=_now().isoformat(),
        )
        out = {
            "access_token": access,
            "refresh_token": refresh,
            "token_type": "bearer",
            "role": user["role"],
            "user_id": user["id"],
            "new_device_alert": new_device,
            "expires_at": row["expires_at"],
            "details": {"integrity": integrity_status(device)},
        }
        restrictions = restrictions_for(user)
        if restrictions is not None:
            out["restrictions"] = restrictions
        return out

    # -- refresh / logout ----------------------------------------------------

    async def refresh(self, refresh_token: str, device_id: str) -> dict:
        h = hash_token(refresh_token or "")
        row = await self._sessions.find_by_refresh_hash(h)
        if row is None:
            burned = await self._sessions.find_burned(h)
            if burned is not None:  # C7: burned-token reuse kills the whole family
                await self._sessions.revoke_family(burned["family_id"])
                log.warning("refresh reuse: family %s revoked", burned["family_id"])
            raise UnauthError("Session expired. Please log in again.", {})
        if row["revoked_at"] is not None or _expired(row["refresh_expires_at"]):
            raise UnauthError("Session expired. Please log in again.", {})
        if device_id != row["device_fp"]:
            raise UnauthError("Session expired. Please log in again.", {})
        _LIMITER.check(f"refresh:user:{row['user_id']}", *REFRESH_USER_LIMIT)
        access, refresh = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
        rotated = await self._sessions.rotate(
            old_refresh_hash=h,
            new_access_hash=hash_token(access),
            new_refresh_hash=hash_token(refresh),
            expires_at=(_now() + _dt.timedelta(minutes=ACCESS_TTL_MIN)).isoformat(),
            refresh_expires_at=(_now() + _dt.timedelta(days=REFRESH_TTL_DAYS)).isoformat(),
        )
        if rotated is None:  # raced logout/reuse between check and rotate
            raise UnauthError("Session expired. Please log in again.", {})
        return {
            "access_token": access,
            "refresh_token": refresh,
            "token_type": "bearer",
            "expires_at": rotated["expires_at"],
        }

    async def logout(self, *, session_id: str, family_id: str, user_id: str,
                   device_id: str, revoke_all: bool = False) -> dict:
        if revoke_all:
            await self._sessions.revoke_family(family_id)
        else:
            await self._sessions.revoke_session(session_id)
        await _delete_device_token(self._conn, user_id, device_id)
        return {"ok": True}

    # -- profile ---------------------------------------------------------------

    async def me(self, user_id: str) -> dict:
        user = await self._users.find_by_id(user_id)
        if user is None:
            raise NotFoundError("User not found.", {"id": user_id})
        out = {
            "user": _public_user(user),
            "addresses_count": await _count(self._conn, "addresses", "user_id", user_id),
            "ledger_summary": await _ledger(self._conn, user_id),
        }
        restrictions = restrictions_for(user)
        if restrictions is not None:
            out["restrictions"] = restrictions
        return out

    async def update_me(self, user_id: str, *, name: str | None = None,
                      language: str | None = None) -> dict:
        if language is not None and not LANG_RE.fullmatch(language):
            raise ValidationError("Unsupported language.", {"language": language})
        if name is not None:
            name = name.strip()[:80]
            if not name:
                raise ValidationError("Name cannot be blank.", {"name": name})
        user = await self._users.update_profile(user_id, name=name, language=language)
        if user is None:
            raise NotFoundError("User not found.", {"id": user_id})
        return {"user": _public_user(user)}


def _expired(iso_ts: str) -> bool:
    try:
        dt = _dt.datetime.fromisoformat(iso_ts)
    except ValueError:
        return True
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=_dt.timezone.utc)
    return dt <= _now()


def _public_user(user: dict) -> dict:
    return {
        "id": user["id"],
        "phone": user["phone"],
        "name": user.get("name"),
        "role": user["role"],
        "language": user.get("language", "hi"),
        "suspended": bool(user.get("suspended")),
    }


async def _table_exists(conn, name: str) -> bool:
    try:
        return (
            await conn.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)
            )
        ).fetchone() is not None
    except Exception:
        return True  # D1 always migrated; the guard is for old local DBs.


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
