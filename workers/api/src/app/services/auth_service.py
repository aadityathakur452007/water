"""Auth service: OTP/demo/customer auth + session lifecycle."""

from __future__ import annotations

import datetime as _dt
import hmac
import secrets
import uuid

from app.adapters.firebase import UnauthError
from app.core.errors import NotFoundError, RateLimitedError, ValidationError
from app.core.passwords import DUMMY_HASH, hash_password, verify_password
from app.db import WRITE_LOCK
from app.repositories.session_repo import SessionRepo
from app.repositories.user_repo import UserRepo
from app.services.auth_helpers import *  # noqa: F401, F403
from app.services.auth_helpers import (  # noqa: F401
    _LIMITER,
    _audit_access_use,
    _backfill_cap,
    _count,
    _delete_device_token,
    _expired,
    _ledger,
    _now,
    _public_user,
    _table_exists,
)
from app.services.auth_staff import AuthStaffMixin


class AuthService(AuthStaffMixin):
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
        user_row = await self._users.find_by_id(user_id)
        if user_row and user_row.get("role") == "user":
            if phone is not None:
                norm_p = normalize_phone(phone.strip())
                curr_p = normalize_phone(user_row.get("phone") or "")
                if norm_p != curr_p:
                    raise ValidationError("Phone number cannot be changed. Contact support.", {"phone": phone})
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
