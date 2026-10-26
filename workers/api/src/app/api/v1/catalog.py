"""Public catalog routes. Rates/hours come from settings (B1: app.core.config)."""
import datetime as dt
import uuid

from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel, Field

from app.api.caching import cached
from app.api.deps import get_db_conn, get_settings
from app.core.errors import ValidationError
from app.schemas.catalog import CatalogOut, SkuOut

router = APIRouter(tags=["catalog"])

_PINCODE_RE = r"^[1-9]\d{5}$"
_HOURS_DEFAULT = "08:00-20:00, all days"
WINDOW_HORIZON_DAYS = 30


def _prefixes() -> list[str]:
    raw = getattr(get_settings(), "serviceable_prefixes", None)
    if raw is None:
        from app.core.worker_env import env_get  # noqa: PLC0415 (request env first)

        raw = env_get("SERVICEABLE_PREFIXES", "")
    if isinstance(raw, str):
        return [p.strip() for p in raw.split(",") if p.strip()]
    return [str(p).strip() for p in raw if str(p).strip()]


def _is_serviceable(pincode: str) -> bool:
    prefixes = _prefixes()
    return not prefixes or any(pincode.startswith(p) for p in prefixes)


@router.get("/catalog")
async def get_catalog(request: Request) -> object:
    # Phase 8 §8.5: cached 5 min + ETag (rates change via deploy/config,
    # not per request). Shape identical to the former response_model.
    s = get_settings()
    return cached(CatalogOut(
        skus=[
            SkuOut(id="refill", price_paise=s.rate_refill_paise),
            SkuOut(id="container", price_paise=s.rate_container_paise),
        ],
        deposit_per_jar=s.deposit_per_jar_paise,
        cap_charge=s.cap_charge_paise,
        hours=str(getattr(s, "business_hours", _HOURS_DEFAULT)),
        holidays=list(getattr(s, "holidays", None) or []),
    ).model_dump(mode="json"), request)


# 014: all-days delivery — Sundays serviceable, holidays still skip.
def _next_serviceable_day(day: dt.date | None) -> dt.date:
    holidays = set(getattr(get_settings(), "holidays", None) or [])
    d = day or dt.date.today()
    while d.isoformat() in holidays:
        d += dt.timedelta(days=1)
    return d


@router.get("/windows")
async def get_windows(request: Request, date: dt.date | None = None,
                pincode: str | None = Query(default=None, pattern=_PINCODE_RE)):
    # Bounded cache cardinality: past dates normalize to today, anything
    # beyond the booking horizon is rejected (audit P1-10).
    today = dt.date.today()
    day_in = date or today
    if day_in < today:
        day_in = today
    if day_in > today + dt.timedelta(days=WINDOW_HORIZON_DAYS):
        raise ValidationError(
            f"Choose a delivery date within the next {WINDOW_HORIZON_DAYS} days.",
            {"date": day_in.isoformat()},
        )
    day = _next_serviceable_day(day_in)
    if pincode is not None and not _is_serviceable(pincode):
        return cached({"date": day.isoformat(), "windows": [], "serviceable": False,
                       "lead_capture": True}, request)
    slots = []
    for h in range(8, 20):
        for m in (0, 30):
            eh, em = (h, 30) if m == 0 else (h + 1, 0)
            slots.append({"start": f"{h:02d}:{m:02d}", "end": f"{eh:02d}:{em:02d}", "capacity_left": None})
    return cached({"date": day.isoformat(), "windows": slots, "serviceable": True}, request)


@router.get("/serviceability")
def check_serviceability(request: Request, pincode: str = Query(pattern=_PINCODE_RE)):
    return cached({"serviceable": _is_serviceable(pincode), "pincode": pincode}, request)


class LeadIn(BaseModel):
    phone: str = Field(min_length=10, max_length=16)
    pincode: str = Field(pattern=_PINCODE_RE)
    lat: float | None = None
    lng: float | None = None


@router.post("/leads", status_code=201)
async def capture_lead(payload: LeadIn, conn=Depends(get_db_conn)):
    """Unserved-pincode lead capture (windows returns lead_capture:true into
    this table). Public by design; rows are human-triaged, never auto-acted on."""
    lid = uuid.uuid4().hex
    await conn.execute(
        "INSERT INTO leads(id, phone, pincode, lat, lng, source, created_at)"
        " VALUES (?, ?, ?, ?, ?, 'windows', ?)",
        (lid, payload.phone.strip(), payload.pincode,
         payload.lat, payload.lng,
         dt.datetime.now(dt.timezone.utc).isoformat()),
    )
    conn.commit()
    return {"id": lid}
