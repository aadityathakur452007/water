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
from app.core.passwords import DUMMY_HASH, hash_password, verify_password
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


def _now() -> _dt.datetime:
    return _dt.datetime.now(_dt.timezone.utc)


class AuthService:
    """Session mint/refresh/logout + profile (constructor injection for tests)."""

    def __init__(self, conn, verifier=None):
        self._conn = conn
        self._users = UserRepo(conn)
        self._sessions = SessionRepo(conn)
        self._verifier = verifier  # duck-typed verify_id_token(); None = only local ops

    async def _limit_check(self, key: str, limit: int, window_s: int) -> None:
        await self._limit_checks([(key, limit, window_s)])

    async def _limit_checks(self, checks: list[tuple[str, int, int]]) -> None:
        """Phase 8 §8.4 + Phase 2: L1 fast-deny + one D1 batch for N keys.

        L1 raises first (per-isolate, instant). D1 (rate_counters keyed by
        key:window-bucket) then denies abuse spread across isolates. One
        multi-row UPSERT plus one IN(...) SELECT makes every check one round
        trip. D1 outage or pre-019 table → debug-logged, L1 still enforced
        (fail-open on counting only — counter writes never fail the auth call
        itself). Keys are server-derived (normalized phone, socket IP, session
        device_fp) — never client-supplied identity (ssdlc).
        """
        for key, limit, window_s in checks:
            _LIMITER.check(key, limit, window_s)  # raises RateLimitedError when over
        try:
            now = time.time()
            dkeys: list[str] = []
            params: list[object] = []
            for key, _, window_s in checks:
                bucket = int(now // window_s) * window_s
                dkey = f"{key}:{bucket}"
                dkeys.append(dkey)
                params.extend([
                    dkey,
                    # Window start is the bucket start (NOT wall-clock now):
                    # every hit in the same window shares one row so the
                    # UPSERT increments instead of scattering count=1 rows.
                    _dt.datetime.fromtimestamp(
                        bucket, tz=_dt.timezone.utc).isoformat(),
                ])
            values = ", ".join("(?, ?, 1)" for _ in checks)
            marks = ", ".join("?" for _ in dkeys)
            results = await self._conn.batch([
                (
                    f"INSERT INTO rate_counters(key, window_start, count)"
                    f" VALUES {values}"
                    " ON CONFLICT(key, window_start) DO UPDATE SET count = count + 1",
                    tuple(params),
                ),
                (
                    f"SELECT key, count FROM rate_counters WHERE key IN ({marks})",
                    tuple(dkeys),
                ),
            ])
            self._conn.commit()
            counts = {r["key"]: int(r["count"]) for r in results[1].fetchall()}
            for (key, limit, window_s), dkey in zip(checks, dkeys):
                count = counts.get(dkey, 0)
                if count > limit:
                    retry = int(window_s - (now % window_s)) or 1
                    log.warning(
                        "rate_limit d1_hit key=%s count=%d limit=%d",
                        key, count, limit,
                    )
                    raise RateLimitedError(
                        "Too many requests.", {"retry_after_s": retry})
        except RateLimitedError:
            raise
        except Exception:  # pre-019 DBs / D1 hiccups: L1 already enforced above
            log.debug("rate_limit d1_unavailable keys=%d", len(checks))

    # -- OTP ---------------------------------------------------------------

    async def otp_start(self, phone: str, ip: str) -> dict:
        phone = normalize_phone(phone)
        await self._limit_check(f"otp-start:phone:{phone}", *OTP_START_PHONE_LIMIT)
        await self._limit_check(f"otp-start:ip:{ip or 'unknown'}", *OTP_START_IP_LIMIT)
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
        await self._limit_check(f"otp-verify:device:{device_id}", *OTP_VERIFY_DEVICE_LIMIT)
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
        try:
            flag = await ConfigRepo(self._conn).get("demo_login_enabled", "0")
        except Exception:  # ADR-054: D1 pre-migration — fail closed, not 500
            flag = None
        if (flag or "0").strip() != "1":
            raise UnauthError("Demo login is off.", {})
        await self._limit_check(f"demo-login:device:{device_id}", *self.DEMO_LOGIN_DEVICE_LIMIT)
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

    VENDOR_LOGIN_DEVICE_LIMIT = (10, 3600)  # same shape as demo abuse cap

    async def vendor_login(
        self, phone: str | None, code: str | None, device_id: str, device: dict | None = None
    ) -> dict:
        """Vendor access-code login (027 RBAC): admin-issued code + vendor role.

        Fail-closed on the ``vendor_access_enabled`` flag (mirrors demo_login).
        No oracle: unknown phone / wrong code / expired / revoked / non-vendor
        all raise the same generic 401. Reuses ``_issue_session`` (30m/7d,
        family, device-cap → 409). The plaintext code is never logged.
        """
        from app.repositories.config_repo import ConfigRepo  # noqa: PLC0415 (lazy seam)
        from app.repositories.vendor_access_repo import VendorAccessRepo  # noqa: PLC0415

        if not (device_id or "").strip():
            raise ValidationError("Device id required.", {"device": "id"})
        try:
            flag = await ConfigRepo(self._conn).get("vendor_access_enabled", "0")
        except Exception:  # pre-migration DB — fail closed, not 500
            flag = None
        if (flag or "0").strip() != "1":
            raise UnauthError("Vendor login is off.", {})
        await self._limit_check(f"vendor-login:device:{device_id}", *self.VENDOR_LOGIN_DEVICE_LIMIT)
        phone_n = normalize_phone(phone or "")
        user = await self._users.find_by_phone(phone_n)
        want = hash_token((code or "").strip())
        matched_id: str | None = None
        if user is not None and user.get("role") == "vendor":
            for row in await VendorAccessRepo(self._conn).find_valid(user["id"]):
                if hmac.compare_digest(str(row["code_hash"]), want):
                    matched_id = str(row["id"])
                    break
        if user is None or user.get("role") != "vendor" or matched_id is None:
            raise UnauthError("Invalid credentials.", {})
        out = await self._issue_session(user, device_id, device)
        await VendorAccessRepo(self._conn).touch_last_used(matched_id)
        try:  # audit must never break the login
            from app.services.dispatch_service import write_audit  # noqa: PLC0415

            with WRITE_LOCK:
                await write_audit(
                    self._conn, actor=user["id"], action="vendor.access.use",
                    entity="vendor_access_codes", entity_id=matched_id,
                )
                self._conn.commit()
        except Exception:
            try:
                self._conn.rollback()
            except Exception:
                pass
            log.warning("vendor.access.use audit failed")
        return out

    # -- access-code login (028 generalized: ONE table for vendor+admin) ------
    # Fail-closed on `access_code_login_enabled == 1` (014 seed defaults 0).
    # Transition compat: vendor doors also honor the legacy
    # `vendor_access_enabled` flag + `vendor_access_codes` table when present
    # (027-seeded DBs); admin doors require the new flag/table only.

    async def code_login(
        self, phone: str | None, code: str | None, device_id: str,
        device: dict | None = None, expected_role: str = "vendor",
    ) -> dict:
        """Phone + admin-issued code → session with absolute 30-day cap.

        No oracle: unknown phone / wrong code / expired / revoked / wrong
        role / flag-off all raise the same generic 401. The plaintext code
        is never logged (only a phone prefix on rate-limit paths).
        """
        from app.repositories.access_code_repo import AccessCodeRepo  # noqa: PLC0415
        from app.repositories.config_repo import ConfigRepo  # noqa: PLC0415

        if not (device_id or "").strip():
            raise ValidationError("Device id required.", {"device": "id"})
        if expected_role not in ("vendor", "admin"):
            raise ValidationError("Unknown role.", {"role": expected_role})
        try:
            flag = await ConfigRepo(self._conn).get("access_code_login_enabled", "0")
        except Exception:  # pre-014 DB — fail closed, not 500
            flag = None
        new_flag_on = (flag or "0").strip() == "1"
        legacy_flag_on = False
        if not new_flag_on and expected_role == "vendor":
            try:
                legacy = await ConfigRepo(self._conn).get("vendor_access_enabled", "0")
            except Exception:  # noqa: BLE001 — no config table at all
                legacy = None
            legacy_flag_on = (legacy or "0").strip() == "1"
        if not (new_flag_on or legacy_flag_on):
            raise UnauthError("Invalid credentials.", {})
        await self._limit_check(f"access-code-login:device:{device_id}", *ACCESS_CODE_DEVICE_LIMIT)
        phone_n = normalize_phone(phone or "")
        user = await self._users.find_by_phone(phone_n)
        want = hash_token((code or "").strip())
        matched_id: str | None = None
        if user is not None and user.get("role") == expected_role:
            try:
                candidates = await AccessCodeRepo(self._conn).find_valid(user["id"])
            except Exception:  # noqa: BLE001 — pre-014 DB without the table
                candidates = []
            for row in candidates:
                if str(row.get("expected_role") or "vendor") != expected_role:
                    continue
                if hmac.compare_digest(str(row["code_hash"]), want):
                    matched_id = str(row["id"])
                    break
            if matched_id is None and expected_role == "vendor":
                # Legacy 027 table fallback (read-only; new issues go to access_codes).
                try:
                    from app.repositories.vendor_access_repo import (  # noqa: PLC0415
                        VendorAccessRepo,
                    )

                    for row in await VendorAccessRepo(self._conn).find_valid(user["id"]):
                        if hmac.compare_digest(str(row["code_hash"]), want):
                            matched_id = str(row["id"])
                            break
                except Exception:  # noqa: BLE001 — legacy table absent, nothing to fall back to
                    pass
                else:
                    if matched_id is not None:
                        out = await self._issue_session(user, device_id, device)
                        try:
                            await VendorAccessRepo(self._conn).touch_last_used(matched_id)
                        except Exception:  # noqa: BLE001
                            pass
                        await _audit_access_use(self._conn, user["id"], matched_id, legacy=True)
                        return out
        if user is None or user.get("role") != expected_role or matched_id is None:
            raise UnauthError("Invalid credentials.", {})
        out = await self._issue_session(user, device_id, device)
        try:
            await AccessCodeRepo(self._conn).touch_last_used(matched_id)
        except Exception:  # noqa: BLE001 — touch must never break login
            pass
        await _audit_access_use(self._conn, user["id"], matched_id, legacy=False)
        return out

    # -- customer password auth (034) -------------------------------------------

    async def user_register(
        self, name: str | None, phone: str | None, email: str | None,
        password: str | None, device_id: str, device: dict | None = None,
        ip: str = "unknown",
    ) -> dict:
        """Create a customer account from name + optional email + phone + password.

        Create-only: an existing phone gets 409 ACCOUNT_EXISTS and never a
        session. There is no OTP migration or account-claim path. The password
        is hashed after the conflict check so a rejected request does not burn
        100k PBKDF2 iterations.
        """
        clean_name = (name or "").strip()
        if not clean_name or len(clean_name) > 100:
            raise ValidationError("Enter your name (1–100 characters).", {"name": name})
        clean_email = normalize_email(email)
        clean_password = validate_password(password)
        if not (device_id or "").strip():
            raise ValidationError("Device id required.", {"device": "id"})
        phone_n = normalize_phone(phone or "")
        await self._limit_check(f"register:phone:{phone_n}", *REGISTER_PHONE_LIMIT)
        await self._limit_check(f"register:ip:{ip or 'unknown'}", *REGISTER_IP_LIMIT)
        existing = await self._users.find_by_phone(phone_n)
        if existing is not None:
            if existing.get("role") != "user":
                raise RoleReservedError(
                    "This number belongs to a staff account. Contact support.",
                    {"phone": mask_phone(phone_n)},
                )
            raise AccountExistsError(
                "This number already has an account. Sign in instead.",
                {"phone": mask_phone(phone_n)},
            )
        password_hash = await hash_password(clean_password)
        try:
            user = await self._users.create_register_user(
                user_id=uuid.uuid4().hex, phone=phone_n, name=clean_name,
                email=clean_email, password_hash=password_hash,
            )
        except Exception as e:  # noqa: BLE001 — unique race between check and insert
            if "unique" in str(e).lower() or "constraint" in str(e).lower():
                raise AccountExistsError(
                    "This number already has an account. Sign in instead.",
                    {"phone": mask_phone(phone_n)},
                ) from e
            raise
        out = await self._issue_session(user, device_id, device)
        out["verified"] = False
        return out

    async def user_login(
        self, phone: str | None, password: str | None,
        device_id: str, device: dict | None = None, ip: str = "unknown",
    ) -> dict:
        """Phone + password login. Unknown/empty/staff credentials are one 401.

        A dummy PBKDF2 verification keeps the no-such-user path close to the
        real one in timing. Customer OTP is never a login proof.
        """
        if not (device_id or "").strip():
            raise ValidationError("Device id required.", {"device": "id"})
        phone_n = normalize_phone(phone or "")
        await self._limit_checks([
            (f"login:phone:{phone_n}", *LOGIN_PHONE_LIMIT),
            (f"login:ip:{ip or 'unknown'}", *LOGIN_IP_LIMIT),
        ])
        user = await self._users.find_for_login_by_phone(phone_n)
        encoded = (user or {}).get("password_hash") or ""
        if user is None or user.get("role") != "user" or not encoded:
            await verify_password(password or "", DUMMY_HASH)
            raise UnauthError("Invalid mobile number or password.", {})
        if not await verify_password(password or "", encoded):
            raise UnauthError("Invalid mobile number or password.", {})
        return await self._issue_session(user, device_id, device)

    async def reset_user_password(
        self, user_id: str, new_password: str | None, *, actor_id: str
    ) -> dict:
        """Admin/support reset: hash a new password, revoke every session, audit."""
        clean_password = validate_password(new_password)
        target = await self._users.find_by_id(user_id)
        if target is None:
            raise NotFoundError("User not found.", {"id": user_id})
        if target.get("role") != "user":
            raise ValidationError(
                "Only customer accounts can have a password reset.",
                {"id": user_id},
            )
        password_hash = await hash_password(clean_password)
        await self._users.set_password(user_id, password_hash)
        revoked = await self._sessions.revoke_user(user_id)
        try:
            from app.services.dispatch_service import write_audit  # noqa: PLC0415

            with WRITE_LOCK:
                await write_audit(
                    self._conn, actor=actor_id, action="user.password_reset",
                    entity="users", entity_id=user_id,
                )
                self._conn.commit()
        except Exception:  # noqa: BLE001 — reset already committed; keep it
            log.exception("password reset audit failed for %s", user_id)
        return {"ok": True, "user_id": user_id, "sessions_revoked": revoked}

    async def _issue_session(self, user: dict, device_id: str, device: dict | None = None) -> dict:
        """Session minting shared by every login path (Firebase, DEV_AUTH,
        demo, vendor/access-code, user-register). Always stamps the absolute
        30-day cap (spec B3) — rotation preserves it, refresh() enforces it."""
        since = (_now() - _dt.timedelta(days=DEVICE_WINDOW_DAYS)).isoformat()
        bound = await self._sessions.device_user_ids(device_id, since)
        if user["id"] not in bound and len(bound) >= DEVICE_CAP:
            raise DeviceCapError(
                "Too many accounts on this device. Contact support.",
                {"device_id": device_id},
            )
        new_device = not await self._sessions.known_device(user["id"], device_id)
        access, refresh = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
        now = _now()
        row = await self._sessions.create(
            user_id=user["id"],
            role=user["role"],
            device_fp=device_id,
            access_hash=hash_token(access),
            refresh_hash=hash_token(refresh),
            family_id=uuid.uuid4().hex,
            expires_at=(now + _dt.timedelta(minutes=ACCESS_TTL_MIN)).isoformat(),
            refresh_expires_at=(now + _dt.timedelta(days=REFRESH_TTL_DAYS)).isoformat(),
            session_expires_at=(now + _dt.timedelta(days=ABSOLUTE_SESSION_DAYS)).isoformat(),
            created_at=now.isoformat(),
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
        # 028 absolute 30-day cap (spec B3/F-refresh): day 30 forces re-login.
        # Plain 401 SESSION_EXPIRED — the family is left intact (no burn), but
        # reuse of a rotated token still burns (handled above). Pre-014 rows
        # without a cap backfill as min(refresh_expires_at, created+30d).
        cap = row.get("session_expires_at")
        if not cap:
            cap = _backfill_cap(row.get("created_at"), row["refresh_expires_at"])
            if cap is not None:
                await self._sessions.set_session_cap(row["id"], cap)
        if cap is not None and _expired(cap):
            raise UnauthError("Session expired. Please log in again.", {})
        await self._limit_check(f"refresh:user:{row['user_id']}", *REFRESH_USER_LIMIT)
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

    async def update_me(
        self,
        user_id: str,
        *,
        name: str | None = None,
        language: str | None = None,
        phone: str | None = None,
        email: str | None = None,
    ) -> dict:
        if language is not None and not LANG_RE.fullmatch(language):
            raise ValidationError("Unsupported language.", {"language": language})
        if name is not None:
            name = name.strip()[:80]
            if not name:
                raise ValidationError("Name cannot be blank.", {"name": name})
        if phone is not None:
            phone = normalize_phone(phone.strip())
            existing = await self._users.find_by_phone(phone)
            if existing is not None and existing.get("id") != user_id:
                if existing.get("role") != "user":
                    raise RoleReservedError(
                        "This number belongs to a staff account. Contact support.",
                        {"phone": mask_phone(phone)},
                    )
                raise PhoneTakenError(
                    "This number is already linked to another account.",
                    {"phone": mask_phone(phone)},
                )
        if email is not None:
            email = normalize_email(email)
        try:
            user = await self._users.update_profile(
                user_id, name=name, language=language, phone=phone, email=email
            )
        except Exception as e:  # noqa: BLE001 — unique race between check and update
            if "unique" in str(e).lower() or "constraint" in str(e).lower():
                raise PhoneTakenError(
                    "This number is already linked to another account.",
                    {"phone": mask_phone(phone or "")},
                ) from e
            raise
        if user is None:
            raise NotFoundError("User not found.", {"id": user_id})
        return {"user": _public_user(user)}


def _expired(iso_ts: str) -> bool:
    try:
        dt = _dt.datetime.fromisoformat(iso_ts)
    except (ValueError, TypeError):
        return True
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=_dt.timezone.utc)
    return dt <= _now()


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
        from app.services.dispatch_service import write_audit  # noqa: PLC0415

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
