"""Public catalog routes. Rates/hours come from settings (B1: app.core.config)."""
import datetime as dt

from fastapi import APIRouter, Query

from app.api.deps import get_settings
from app.schemas.catalog import CatalogOut, SkuOut

router = APIRouter(tags=["catalog"])

_PINCODE_RE = r"^[1-9]\d{5}$"
_HOURS_DEFAULT = "08:00-20:00, closed Sundays"


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


@router.get("/catalog", response_model=CatalogOut)
def get_catalog() -> CatalogOut:
    s = get_settings()
    return CatalogOut(
        skus=[
            SkuOut(id="refill", price_paise=s.rate_refill_paise),
            SkuOut(id="container", price_paise=s.rate_container_paise),
        ],
        deposit_per_jar=s.deposit_per_jar_paise,
        cap_charge=s.cap_charge_paise,
        hours=str(getattr(s, "business_hours", _HOURS_DEFAULT)),
        holidays=list(getattr(s, "holidays", None) or []),
    )


def _next_serviceable_day(day: dt.date | None) -> dt.date:
    holidays = set(getattr(get_settings(), "holidays", None) or [])
    d = day or dt.date.today()
    while d.weekday() == 6 or d.isoformat() in holidays:  # ex-Sun
        d += dt.timedelta(days=1)
    return d


@router.get("/windows")
def get_windows(date: dt.date | None = None, pincode: str | None = Query(default=None, pattern=_PINCODE_RE)):
    day = _next_serviceable_day(date)
    if pincode is not None and not _is_serviceable(pincode):
        return {"date": day.isoformat(), "windows": [], "serviceable": False, "lead_capture": True}
    slots = []
    for h in range(8, 20):
        for m in (0, 30):
            eh, em = (h, 30) if m == 0 else (h + 1, 0)
            slots.append({"start": f"{h:02d}:{m:02d}", "end": f"{eh:02d}:{em:02d}", "capacity_left": None})
    return {"date": day.isoformat(), "windows": slots, "serviceable": True}


@router.get("/serviceability")
def check_serviceability(pincode: str = Query(pattern=_PINCODE_RE)):
    return {"serviceable": _is_serviceable(pincode), "pincode": pincode}
