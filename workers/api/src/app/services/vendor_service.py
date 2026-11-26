"""Vendor ops service facade combining duty, routes/PoD, and fleet/profile mixins."""

from __future__ import annotations

from app.repositories.ledger_repo import LedgerRepo
from app.services.vendor._common import (  # noqa: F401
    CASH_ENDPOINT,
    Conn,
    DeliveryCodeExpiredError,
    DeliveryCodeUnavailableError,
    GPS_FLAG_M,
    POD_MAX_ATTEMPTS,
    PayloadMismatchError,
    PodLockedError,
    RIDER_CODE_TTL_DAYS,
    StaleStopError,
    TRIPLE_ENDPOINT,
    _decode_cursor,
    _encode_cursor,
    _ensure_stop_cancel_cols,
    _has_pod_cols,
    _haversine_m,
    _now,
    _parse_items,
    _pod_lifecycle,
    _stop_field_cols,
    _today,
    _triple_core,
)
from app.services.vendor.duty import VendorDutyMixin
from app.services.vendor.fleet_and_profile import VendorFleetMixin
from app.services.vendor.routes import VendorRoutesMixin


class VendorService(VendorDutyMixin, VendorRoutesMixin, VendorFleetMixin):
    """Service-per-use-case for vendor ops."""

    def __init__(self, conn: Conn):
        self._conn = conn
        self.ledger = LedgerRepo(conn)
