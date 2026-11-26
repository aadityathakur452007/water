from __future__ import annotations

import datetime as _dt
import hmac

from app.adapters.firebase import UnauthError
from app.core.errors import ValidationError
from app.services.auth_helpers import *  # noqa: F401, F403
from app.services.auth_helpers import _audit_access_use


class AuthStaffMixin:
    VENDOR_LOGIN_DEVICE_LIMIT = (10, 3600)

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
        if user is None or user.get("role") != "vendor":
            raw_phone = (phone or "").strip()
            row = (await self._conn.execute(
                "SELECT * FROM users WHERE (phone = ? OR phone = ?) AND role = 'vendor' LIMIT 1",
                (phone_n, raw_phone),
            )).fetchone()
            if row is not None:
                user = dict(row)
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
        if expected_role not in ("vendor", "admin", "rider"):
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
        if user is None or user.get("role") != expected_role:
            raw_phone = (phone or "").strip()
            row = (await self._conn.execute(
                "SELECT * FROM users WHERE (phone = ? OR phone = ?) AND role = ? LIMIT 1",
                (phone_n, raw_phone, expected_role),
            )).fetchone()
            if row is not None:
                user = dict(row)
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
        if expected_role == "vendor":
            try:
                now_iso = _dt.datetime.now(_dt.timezone.utc).isoformat()
                await self._conn.execute(
                    "UPDATE vendor_profile SET on_duty = 1, duty_on = COALESCE(duty_on, ?) WHERE user_id = ?",
                    (now_iso, user["id"]),
                )
            except Exception:
                pass
        try:
            await AccessCodeRepo(self._conn).touch_last_used(matched_id)
        except Exception:  # noqa: BLE001 — touch must never break login
            pass
        await _audit_access_use(self._conn, user["id"], matched_id, legacy=False)
        return out

    async def rider_login(
        self, phone: str | None, name: str | None, code: str | None,
        device_id: str, device: dict | None = None,
    ) -> dict:
        """Rider login: registered mobile number + vendor-issued access code.

        The vendor mints the code at onboarding (`POST /v1/vendor/riders`) and
        rotates it with `POST /v1/vendor/riders/{id}/code`; only its sha256
        lands in `access_codes` with ``expected_role='rider'``. A phone number
        is public, so it can never be the only factor.
        """
        from app.repositories.access_code_repo import AccessCodeRepo  # noqa: PLC0415

        if not (device_id or "").strip():
            raise ValidationError("Device id required.", {"device": "id"})
        phone_n = normalize_phone(phone or "")
        await self._limit_checks([
            (f"rider_login:phone:{phone_n}", *LOGIN_PHONE_LIMIT),
            (f"rider_login:device:{device_id}", *ACCESS_CODE_DEVICE_LIMIT),
        ])

        user = await self._users.find_by_phone(phone_n)
        if user is not None and (user.get("role") != "rider" or user.get("suspended")):
            user = None

        want = hash_token((code or "").strip())
        matched_id: str | None = None
        if user is not None:
            for cand in await AccessCodeRepo(self._conn).find_valid(user["id"]):
                if (str(cand.get("expected_role") or "") == "rider"
                        and hmac.compare_digest(str(cand["code_hash"]), want)):
                    matched_id = str(cand["id"])
                    break

        # One generic error for unknown numbers, wrong/missing/expired/revoked
        # codes and suspended riders — this door is not an account oracle.
        if user is None or matched_id is None:
            raise UnauthError("Invalid credentials.", {})

        await AccessCodeRepo(self._conn).touch_last_used(matched_id)

        if name and name.strip() and (not user.get("name") or user.get("name") == "Rider"):
            with WRITE_LOCK:
                try:
                    await self._conn.execute(
                        "UPDATE users SET name = ? WHERE id = ?",
                        (name.strip(), user["id"]),
                    )
                    self._conn.commit()
                    user["name"] = name.strip()
                except Exception:
                    pass

        return await self._issue_session(user, device_id, device)
