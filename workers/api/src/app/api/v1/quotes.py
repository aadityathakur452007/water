"""Quote route: Pydantic boundary validation -> pure pricing service -> 200 quote.

OVER_LIMIT uses an AppError subclass (B1's hierarchy pattern: per-error code +
status_code as class attrs); B1's central handler renders the contract envelope.
Pydantic boundary failures surface via B1's validation handler (400 VALIDATION).
"""
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter

from app.api.deps import get_settings
from app.core.errors import AppError
from app.schemas.catalog import QuoteIn, QuoteOut
from app.services import pricing

router = APIRouter(tags=["quotes"])

MAX_JARS_PER_QUOTE = 10  # EC-O03 hard stop; tanker-stop policy lives in orders (B3)


class OverLimitError(AppError):
    code = "OVER_LIMIT"
    status_code = 422


@router.post("/quotes", response_model=QuoteOut, status_code=200)
async def create_quote(payload: QuoteIn) -> QuoteOut:
    s = get_settings()
    q = pricing.compute_quote(
        [{"sku": i.sku, "qty": i.qty} for i in payload.items],
        payload.e,
        {
            "refill": s.rate_refill_paise,
            "container": s.rate_container_paise,
            "deposit": s.deposit_per_jar_paise,
        },
        address_id=payload.address_id,
        window_start=payload.window_start,
        rate_version=str(getattr(s, "rate_version", pricing.RATE_VERSION)),
    )
    if q["n_total"] > MAX_JARS_PER_QUOTE:
        raise OverLimitError(
            message="Maximum 10 jars per order. For larger (tanker) requirements, please contact support.",
            details={"n": q["n_total"], "max": MAX_JARS_PER_QUOTE},
        )
    ttl = int(getattr(s, "quote_ttl_minutes", 15))
    return QuoteOut(
        water_bill=q["water_bill"],
        deposit_due=q["deposit_due"],
        cap_note=q["cap_note"],
        total=q["total"],
        quote_hash=q["quote_hash"],
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=ttl),
    )
