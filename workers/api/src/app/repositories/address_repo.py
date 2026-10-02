"""Address repository — the only place that touches ``addresses`` SQL.

Services/routers stay DB-agnostic; FastAPI injects this via ``Depends``.
All queries parameterized (ssdlc). IDOR: get/update/delete are owner-scoped
(``WHERE id=? AND user_id=?``); miss returns None/False so routes render the
same-shape 404 as not-found (no owner oracle, contract §3).

Edit guards: update/delete refuse while an ACTIVE order references the address
(state NOT IN delivered/cancelled/failed/rejected) or — for delete — an active
subscription does. ``orders``/``subscriptions`` tables may not exist yet
(slice-2/3); guard queries check sqlite_master first and skip when absent.

Async (Phase-B T2): methods await the shared facade (D1 in prod, sqlite
locally) — call shapes are otherwise unchanged.
"""

from __future__ import annotations

import datetime as _dt
import re
import sqlite3
import uuid

from app.core.errors import ConflictError, ValidationError
from app.db import WRITE_LOCK
from app.db_d1 import AsyncSqliteConn, D1Conn

Conn = D1Conn | AsyncSqliteConn

_PINCODE_RE = re.compile(r"^[1-9]\d{5}$")
_VALID_TYPES = ("home", "office")
# Terminal order states (contract §2 machine); anything else is active/in-flight.
_TERMINAL_STATES = ("delivered", "cancelled", "failed", "rejected")

_UPDATABLE = ("type", "label", "lat", "lng", "place_id", "formatted", "landmark", "pincode", "lift_flag",
              "house", "street", "area", "phone")  # 011_port: full address format
# Nullable text columns: explicit null clears the value; other Nones mean "no change".
_NULLABLE_TEXT = ("label", "place_id", "formatted", "landmark", "house", "street", "area", "phone")


def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).isoformat()


async def _table_exists(conn: Conn, name: str) -> bool:
    row = (
        await conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,))
    ).fetchone()
    return row is not None


def _field(dto, name: str, default=None):
    if isinstance(dto, dict):
        return dto.get(name, default)
    return getattr(dto, name, default)


def _validate(type_=None, lat=None, lng=None, pincode=None, **capped) -> None:
    if type_ is not None and type_ not in _VALID_TYPES:
        raise ValidationError("type must be home|office", {"type": type_})
    if lat is not None and not (-90 <= float(lat) <= 90):
        raise ValidationError("lat must be -90..90", {"lat": lat})
    if lng is not None and not (-180 <= float(lng) <= 180):
        raise ValidationError("lng must be -180..180", {"lng": lng})
    if lat is not None and lng is not None and float(lat) == 0 and float(lng) == 0:
        raise ValidationError("GPS fix required — (0,0) is not a valid location", {})
    if pincode is not None and not _PINCODE_RE.match(str(pincode).strip()):
        raise ValidationError("pincode must be 6 digits, not starting with 0", {"pincode": pincode})
    # F1 caps (ADR-056): defense in depth for direct repo callers (Pydantic
    # already gates the HTTP path). 500 chars like complaints/vendor notes.
    for k, v in capped.items():
        if v is not None and len(str(v)) > 500:
            raise ValidationError(f"{k} must be ≤ 500 chars", {k: k})


def _row_to_dict(row: sqlite3.Row) -> dict:
    return dict(row)


class AddressRepo:
    """Data access for user addresses."""

    def __init__(self, conn: Conn):
        self._conn = conn

    async def create(self, user_id: str, dto, serviceable: bool | None = None) -> dict:
        type_ = _field(dto, "type")
        lat = _field(dto, "lat")
        lng = _field(dto, "lng")
        pincode = _field(dto, "pincode")
        _validate(type_, lat, lng, pincode, house=_field(dto, "house"),
                  street=_field(dto, "street"), area=_field(dto, "area"),
                  phone=_field(dto, "phone"))
        now = _now()
        addr_id = uuid.uuid4().hex
        lift = 1 if _field(dto, "lift_flag", False) else 0
        svc = 1 if (serviceable if serviceable is not None else True) else 0
        with WRITE_LOCK:
            await self._conn.execute(
                "INSERT INTO addresses(id, user_id, type, label, lat, lng, place_id,"
                " formatted, landmark, pincode, lift_flag, serviceable, created_at,"
                " house, street, area, phone)"
                " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    addr_id,
                    user_id,
                    type_,
                    _field(dto, "label"),
                    float(lat),
                    float(lng),
                    _field(dto, "place_id"),
                    _field(dto, "formatted"),
                    _field(dto, "landmark"),
                    str(pincode).strip(),
                    lift,
                    svc,
                    now,
                    _field(dto, "house"),
                    _field(dto, "street"),
                    _field(dto, "area"),
                    _field(dto, "phone"),
                ),
            )
            self._conn.commit()
        return (await self.get_owned(addr_id, user_id)) or {"id": addr_id}

    async def list_by_user(self, user_id: str) -> list[dict]:
        rows = (
            await self._conn.execute(
                "SELECT * FROM addresses WHERE user_id = ? ORDER BY created_at DESC", (user_id,)
            )
        ).fetchall()
        return [_row_to_dict(r) for r in rows]

    async def get_owned(self, addr_id: str, user_id: str) -> dict | None:
        row = (
            await self._conn.execute(
                "SELECT * FROM addresses WHERE id = ? AND user_id = ?", (addr_id, user_id)
            )
        ).fetchone()
        return _row_to_dict(row) if row is not None else None

    async def _blocked_by_order(self, addr_id: str) -> bool:
        if not await _table_exists(self._conn, "orders"):
            return False
        try:
            row = (
                await self._conn.execute(
                    "SELECT 1 FROM orders WHERE address_id = ? AND state NOT IN (?, ?, ?, ?) LIMIT 1",
                    (addr_id, *_TERMINAL_STATES),
                )
            ).fetchone()
        except sqlite3.OperationalError:
            return False  # schema drift (no address_id/state yet) → skip, don't block
        return row is not None

    async def _blocked_by_sub(self, addr_id: str) -> bool:
        if not await _table_exists(self._conn, "subscriptions"):
            return False
        try:
            row = (
                await self._conn.execute(
                    "SELECT 1 FROM subscriptions WHERE address_id = ? AND status = 'active' LIMIT 1",
                    (addr_id,),
                )
            ).fetchone()
        except sqlite3.OperationalError:
            return False
        return row is not None

    async def update_owned(self, addr_id: str, user_id: str, patch, serviceable: bool | None = None) -> dict | None:
        current = await self.get_owned(addr_id, user_id)
        if current is None:
            return None
        data = patch if isinstance(patch, dict) else patch.model_dump(exclude_unset=True)
        fields: dict = {}
        for k in _UPDATABLE:
            if k not in data:
                continue
            v = data[k]
            if v is None and k not in _NULLABLE_TEXT:
                continue
            fields[k] = v
        # Merged coords for the (0,0) check: unset side falls back to stored value.
        new_lat = fields.get("lat", current["lat"])
        new_lng = fields.get("lng", current["lng"])
        touching_geo = "lat" in fields or "lng" in fields
        _validate(
            fields.get("type"),
            new_lat if touching_geo else None,
            new_lng if touching_geo else None,
            fields.get("pincode"),
            house=fields.get("house"), street=fields.get("street"),
            area=fields.get("area"), phone=fields.get("phone"),
        )
        if await self._blocked_by_order(addr_id):
            raise ConflictError(
                "Address is linked to an active order and cannot be edited",
                {"address_id": addr_id},
            )
        sets, params = [], []
        for k in _UPDATABLE:
            if k in fields:
                v = fields[k]
                if k == "lift_flag":
                    v = 1 if v else 0
                if k == "pincode" and v is not None:
                    v = str(v).strip()
                if k == "phone" and v is not None:
                    v = str(v).strip()  # permissive: stored as given, no format gate (011)
                sets.append(f"{k} = ?")
                params.append(v)
        if serviceable is not None and "pincode" in fields:
            sets.append("serviceable = ?")
            params.append(1 if serviceable else 0)
        if not sets:
            return current
        params.extend([addr_id, user_id])
        with WRITE_LOCK:
            await self._conn.execute(
                f"UPDATE addresses SET {', '.join(sets)} WHERE id = ? AND user_id = ?", params
            )
            self._conn.commit()
        return await self.get_owned(addr_id, user_id)

    async def delete_owned(self, addr_id: str, user_id: str) -> bool:
        if await self.get_owned(addr_id, user_id) is None:
            return False
        if await self._blocked_by_order(addr_id) or await self._blocked_by_sub(addr_id):
            raise ConflictError(
                "Address has active orders/subscriptions and cannot be deleted",
                {"address_id": addr_id},
            )
        with WRITE_LOCK:
            cur = await self._conn.execute(
                "DELETE FROM addresses WHERE id = ? AND user_id = ?", (addr_id, user_id)
            )
            self._conn.commit()
        return cur.rowcount > 0
