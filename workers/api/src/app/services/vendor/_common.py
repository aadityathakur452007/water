"""Vendor ops service — business rules ONLY (no SQL outside repo calls + stop SQL, no FastAPI).

Owns (contract §4.7 + §9.2 + §11 + §12 + §14.3): duty flag, today route sheet,
atomic triple commit, PoD with OTP + soft GPS flag, offline sync batch,
earnings with flagged-hold note, complaint verify, quality door-check.

Scope deviations (documented, ponytail-minimal):
- Duty persists on vendor_profile.on_duty (F5, via ensure_profile column
  convergence — 007 vs 011 shape conflict resolved in code, no migration).
- Delivery codes are random 6-digit secrets minted at assignment, armed for
  24h at dispatch (``stops.pod_otp_expires_at``, 027), and deleted on use,
  terminal failure/cancel, or expiry. Wrong codes read as not-found (no
  oracle) and lock after five attempts; there is no deterministic fallback.
- Quality door-checks write the quality_incidents table (F4, single truth).
- Cash posts to money truth via POST .../cash → mark_paid_cash (F2);
  in_hand custody bumps with duty convergence (F5).
"""

from __future__ import annotations

import json
import math

from app.core.errors import AppError, ValidationError
from app.db import WRITE_LOCK
from app.db_d1 import AsyncSqliteConn, D1Conn
from app.db_schema import order_columns, stop_columns

Conn = D1Conn | AsyncSqliteConn

GPS_FLAG_M = 200.0  # §12: drift beyond this soft-flags for admin, never blocks
RIDER_CODE_TTL_DAYS = 90  # rider sign-in code lifetime; re-onboard to reissue

TRIPLE_ENDPOINT = "POST /v1/vendor/stops/{id}/triple"
CASH_ENDPOINT = "POST /v1/vendor/stops/{id}/cash"


class StaleStopError(AppError):
    code = "STALE_STOP"
    status_code = 409


class PodLockedError(AppError):
    code = "POD_LOCKED"
    status_code = 429


class DeliveryCodeExpiredError(AppError):
    code = "DELIVERY_CODE_EXPIRED"
    status_code = 410


class DeliveryCodeUnavailableError(AppError):
    code = "DELIVERY_CODE_UNAVAILABLE"
    status_code = 410


class PayloadMismatchError(AppError):
    code = "PAYLOAD_MISMATCH"
    status_code = 422


# -- module seams ---------------------------------------------------------------
# (F4/F5 retired the _QUALITY/_DUTY in-memory stores to their tables.)




from app.core.time_utils import utc_now_iso as _now, utc_today_iso as _today  # noqa: F401


def _decode_cursor(cursor: str) -> tuple[str, str] | None:
    """Phase 8 §8.2: base64url created_at|id cursor (same shape as order
    list_by_user). Bad cursor → 400, never a silent full re-read."""
    if not cursor:
        return None
    import base64

    try:
        ts, _, oid = base64.urlsafe_b64decode(cursor.encode()).decode().rpartition("|")
        if not ts or not oid:
            raise ValueError
    except (ValueError, UnicodeDecodeError):
        raise ValidationError(message="Bad cursor.", details={}) from None
    return ts, oid


def _encode_cursor(created_at: str, row_id: str) -> str:
    import base64

    return base64.urlsafe_b64encode(f"{created_at}|{row_id}".encode()).decode()


POD_MAX_ATTEMPTS = 5  # wrong codes per stop before the stop locks (DB-backed)


async def _has_pod_cols(conn: Conn) -> bool:
    """Whether this DB has the 015 columns (tolerates pre-migration DBs)."""
    names = await stop_columns(conn)
    return "pod_otp" in names and "pod_attempts" in names


async def _pod_lifecycle(conn: Conn, stop_id: str) -> dict:
    """Read code, attempts, and expiry together (tolerant of pre-015/027)."""
    cols = await stop_columns(conn)
    if not cols:
        return {"has_otp": False, "has_expiry": False,
                "code": None, "attempts": 0, "expires_at": None}
    selected = ["id"]
    for name in ("pod_otp", "pod_attempts", "pod_otp_expires_at"):
        if name in cols:
            selected.append(name)
    row = (await conn.execute(
        f"SELECT {', '.join(selected)} FROM stops WHERE id = ?", (stop_id,)  # noqa: S608
    )).fetchone()
    if row is None:
        return {"has_otp": False, "has_expiry": False,
                "code": None, "attempts": 0, "expires_at": None}
    return {
        "has_otp": "pod_otp" in cols and "pod_attempts" in cols,
        "has_expiry": "pod_otp_expires_at" in cols,
        "code": str(row["pod_otp"]) if "pod_otp" in cols and row["pod_otp"] else None,
        "attempts": int(row["pod_attempts"] or 0) if "pod_attempts" in cols else 0,
        "expires_at": row["pod_otp_expires_at"] if "pod_otp_expires_at" in cols else None,
    }


async def _stop_field_cols(conn: Conn) -> dict[str, bool]:
    """016/023 presence flags (tolerates pre-migration DBs)."""
    stops_cols = await stop_columns(conn)
    order_cols = await order_columns(conn)
    return {
        "items_json": "items_json" in stops_cols,
        "failure_reason": "failure_reason" in stops_cols,
        "instructions": "instructions" in order_cols,
        "address_snapshot_json": "address_snapshot_json" in order_cols,
    }


def _parse_items(raw: object) -> list:
    """Order/stop SKU snapshot as a list (NULL/garbage → [])."""
    if not raw:
        return []
    try:
        items = json.loads(raw) if isinstance(raw, str) else raw
    except (ValueError, TypeError):
        return []
    return items if isinstance(items, list) else []


def _haversine_m(a_lat: float, a_lng: float, b_lat: float, b_lng: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    dp = math.radians(b_lat - a_lat)
    dl = math.radians(b_lng - a_lng)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def _triple_core(t: dict) -> dict:
    return {k: int(t.get(k, 0)) for k in ("fulls_given", "empties_back", "cash", "upi", "caps_missing")}




async def _ensure_stop_cancel_cols(conn) -> None:
    try:
        cols = {r["name"] for r in (await conn.execute("SELECT name FROM pragma_table_info('stops')")).fetchall()}
        if "cancel_otp" not in cols:
            with WRITE_LOCK:
                await conn.execute("ALTER TABLE stops ADD COLUMN cancel_otp TEXT")
                conn.commit()
        if "cancel_otp_created_at" not in cols:
            with WRITE_LOCK:
                await conn.execute("ALTER TABLE stops ADD COLUMN cancel_otp_created_at TEXT")
                conn.commit()
    except Exception:
        pass

