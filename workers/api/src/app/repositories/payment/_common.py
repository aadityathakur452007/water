"""Payment repository — the only place that touches ``payments`` SQL.

Paise integers, parameterized writes (ssdlc), one-transaction mutating calls
(WRITE_LOCK). Webhook dedup (C16): UNIQUE(provider_ref) — duplicate delivery
returns the existing row, never a second credit. Payee lock (§14.4): collections
only to ``AGENCY_UPI_VPA``. Refund claim lock (C15): single claimant wins.

Async (Phase-B T2): methods await the shared facade (D1 in prod, sqlite
locally) — call shapes are otherwise unchanged.
"""

from __future__ import annotations

import datetime as _dt
import hashlib

from app.core.errors import AppError
from app.db_d1 import AsyncSqliteConn, D1Conn

Conn = D1Conn | AsyncSqliteConn

INTENT_ENDPOINT = "POST /v1/payments/upi-intent"

_CHUNK = 90  # D1 allows 100 bound parameters per statement


class AmountMismatchError(AppError):
    code = "AMOUNT_MISMATCH"
    status_code = 422


class PayeeMismatchError(AppError):
    code = "PAYEE_MISMATCH"
    status_code = 422


class PayloadMismatchError(AppError):
    code = "PAYLOAD_MISMATCH"
    status_code = 422


class RefundClaimError(AppError):
    code = "REFUND_CLAIM_CONFLICT"
    status_code = 409


class OverpayError(AppError):
    code = "OVERPAY"
    status_code = 422


class IntentPendingError(AppError):
    code = "INTENT_PENDING"
    status_code = 409



from app.core.time_utils import utc_now_iso as _now  # noqa: F401


def _stale(created_at: object, minutes: int = 10) -> bool:
    """True when a pending reservation is old enough to be safely retried."""
    try:
        created = _dt.datetime.fromisoformat(str(created_at))
    except (TypeError, ValueError):
        return False
    if created.tzinfo is None:
        created = created.replace(tzinfo=_dt.timezone.utc)
    return _dt.datetime.now(_dt.timezone.utc) - created > _dt.timedelta(minutes=minutes)


def _intent_link(provider_ref: str, amount: int) -> str:
    """Rebuild the UPI deep link for an already-minted provider order."""
    return (f"upi://pay?pa={_agency_vpa()}&pn=Shodasha&am={int(amount) / 100:.2f}"
            f"&tr={provider_ref}&cu=INR")


def _agency_vpa() -> str:
    from app.core.config import Settings  # noqa: PLC0415
    from app.core.worker_env import env_get  # noqa: PLC0415

    vpa = env_get("AGENCY_UPI_VPA") or getattr(Settings(), "agency_upi_vpa", None)
    return str(vpa) if vpa else "shodasha@upi"


def _payload_hash(order_id: str, amount: int) -> str:
    return hashlib.sha256(f"{order_id}:{int(amount)}".encode()).hexdigest()


def _payment_guard(payment_id: str, token: str) -> tuple[str, tuple]:
    """SQL condition only the batch that wrote ``settlement_token`` sees."""
    return ("EXISTS (SELECT 1 FROM payments WHERE id = ? AND settlement_token = ?)",
            (payment_id, token))


def _refund_worthy(order_id: str) -> tuple[str, tuple]:
    """A capture must be refunded when the order is dead, COD, or already paid."""
    return (
        "EXISTS (SELECT 1 FROM orders WHERE id = ?"
        " AND (state IN ('cancelled','rejected') OR payment_mode = 'cod'"
        " OR payment_status IN ('paid_upi','paid_cash')))",
        (order_id,),
    )


def _can_mark_paid(order_id: str) -> tuple[str, tuple]:
    """The only order state a normal UPI capture may settle."""
    return (
        "EXISTS (SELECT 1 FROM orders WHERE id = ?"
        " AND state NOT IN ('cancelled','rejected')"
        " AND payment_mode != 'cod'"
        " AND payment_status NOT IN ('paid_upi','paid_cash'))",
        (order_id,),
    )

