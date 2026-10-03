"""Pure quote math. No FastAPI imports. All money integer paise.

deposit_due = max(0, N-E) * deposit; water_bill = refills*refill + containers*container.
OVER_LIMIT policy (N>10) is NOT enforced here — the service returns n_total and the
route maps N>10 to 422 OVER_LIMIT (home-vs-office policy needs address type, B3 slice).
"""
import hashlib
import json

REFILL_PAISE = 2800
CONTAINER_PAISE = 3000
DEPOSIT_PAISE = 15000
CAP_PAISE = 300
RATE_VERSION = "v1"
CAP_NOTE = "Rs 3/jar extra only if a returned empty is missing its cap (counted at handover)."


def _sku_qty(item):
    if isinstance(item, dict):
        return item["sku"], int(item.get("qty", 0))
    return item.sku, int(item.qty)


def compute_quote(items, e, rates=None, address_id="", window_start="", rate_version=RATE_VERSION,
                    deposit_already_paid_paise=0):
    rates = rates or {}
    refill = int(rates.get("refill", REFILL_PAISE))
    container = int(rates.get("container", CONTAINER_PAISE))
    deposit = int(rates.get("deposit", DEPOSIT_PAISE))
    n_refill = n_container = 0
    norm = []
    for it in items:
        sku, qty = _sku_qty(it)
        if sku not in ("refill", "container"):
            raise ValueError(f"unknown sku: {sku}")
        norm.append({"sku": sku, "qty": qty})
        if sku == "refill":
            n_refill += qty
        else:
            n_container += qty
    n_total = n_refill + n_container
    water_bill = n_refill * refill + n_container * container
    # Once-only deposit: refill never carries deposit; container carries
    # (n_container - empties_against_containers) only when the wallet does
    # not already hold >= one deposit. Damage/quit settlement stays in ledger.
    if n_container <= 0 or int(deposit_already_paid_paise or 0) >= deposit:
        deposit_due = 0
    else:
        e_vs_containers = max(0, min(int(e), n_container))
        deposit_due = max(0, n_container - e_vs_containers) * deposit
    total = water_bill + deposit_due
    canonical = json.dumps(
        {
            "items": sorted(norm, key=lambda x: x["sku"]),
            "e": int(e),
            "address_id": address_id,
            "window": window_start,
            "total": total,
            "rate_version": rate_version,
        },
        sort_keys=True,
        separators=(",", ":"),
    )
    return {
        "water_bill": water_bill,
        "deposit_due": deposit_due,
        "cap_note": CAP_NOTE,
        "total": total,
        "quote_hash": hashlib.sha256(canonical.encode()).hexdigest(),
        "n_total": n_total,
        "rate_version": rate_version,
    }
