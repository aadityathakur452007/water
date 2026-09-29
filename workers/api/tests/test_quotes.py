"""B2 slice-1 tests: pure pricing math + Pydantic boundary + router via TestClient.

Pure tests never touch B1 files. Router tests run against B1's real app factory
(app.main.create_app), so status codes/envelopes are production truth:
Pydantic boundary failures -> 400 VALIDATION (B1 handler, contract §0),
N>10 -> 422 OVER_LIMIT.
"""
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from pydantic import ValidationError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.schemas.catalog import QuoteIn
from app.services import pricing

RATES = {"refill": 2800, "container": 3000, "deposit": 15000}


def test_worked_example_2_refills_1_empty():
    q = pricing.compute_quote(
        [{"sku": "refill", "qty": 2}], 1, RATES, address_id="a1", window_start="2026-09-30T08:00:00Z"
    )
    assert q["water_bill"] == 5600
    assert q["deposit_due"] == 15000
    assert q["total"] == 20600


def test_mixed_skus_deposit_on_uncovered_only():
    q = pricing.compute_quote([{"sku": "refill", "qty": 2}, {"sku": "container", "qty": 1}], 2, RATES)
    assert q["water_bill"] == 5600 + 3000
    assert q["deposit_due"] == 15000
    assert q["total"] == 5600 + 3000 + 15000
    assert q["n_total"] == 3


def test_over_limit_surfaces_n_total_for_route():
    q = pricing.compute_quote([{"sku": "refill", "qty": 10}, {"sku": "container", "qty": 1}], 0, RATES)
    assert q["n_total"] == 11  # route maps N>10 -> 422 OVER_LIMIT


def test_empty_order_rejected_at_boundary():
    with pytest.raises(ValidationError):
        QuoteIn(items=[{"sku": "refill", "qty": 0}], e=0, address_id="a1", window_start="w")


def test_empties_above_total_rejected_at_boundary():
    with pytest.raises(ValidationError):
        QuoteIn(items=[{"sku": "refill", "qty": 2}], e=3, address_id="a1", window_start="w")


def test_quote_hash_stable_and_sensitive():
    base = dict(items=[{"sku": "refill", "qty": 2}], e=1, rates=RATES, address_id="a1", window_start="w")
    assert pricing.compute_quote(**base)["quote_hash"] == pricing.compute_quote(**base)["quote_hash"]
    changed = dict(base, e=2)
    assert pricing.compute_quote(**changed)["quote_hash"] != pricing.compute_quote(**base)["quote_hash"]


def _client():
    pytest.importorskip("httpx")
    create_app = pytest.importorskip("app.main", reason="B1 app factory missing").create_app
    from fastapi.testclient import TestClient

    return TestClient(create_app())


def _quote_payload():
    return {
        "items": [{"sku": "refill", "qty": 2}],
        "e": 1,
        "address_id": "a1",
        "window_start": "2026-09-30T08:00:00Z",
    }


def test_router_quote_200_and_expiry():
    c = _client()
    r = c.post("/v1/quotes", json=_quote_payload())
    assert r.status_code == 200, r.text
    body = r.json()
    assert (body["water_bill"], body["deposit_due"], body["total"]) == (5600, 15000, 20600)
    assert len(body["quote_hash"]) == 64
    delta = datetime.fromisoformat(body["expires_at"]) - datetime.now(timezone.utc)
    assert timedelta(minutes=14) < delta <= timedelta(minutes=16)


def test_router_empty_order_400():
    c = _client()
    r = c.post("/v1/quotes", json=_quote_payload() | {"items": [{"sku": "refill", "qty": 0}], "e": 0})
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION"


def test_router_empties_above_total_400():
    c = _client()
    r = c.post("/v1/quotes", json=_quote_payload() | {"e": 3})
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION"


def test_router_over_limit_422():
    c = _client()
    r = c.post("/v1/quotes", json=_quote_payload() | {"items": [
        {"sku": "refill", "qty": 10},
        {"sku": "container", "qty": 1},
    ]})
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "OVER_LIMIT"


def test_router_catalog_200():
    c = _client()
    r = c.get("/v1/catalog")
    assert r.status_code == 200, r.text
    body = r.json()
    assert [s["price_paise"] for s in body["skus"]] == [2800, 3000]
    assert (body["deposit_per_jar"], body["cap_charge"]) == (15000, 300)


def test_router_bad_pincode_400():
    c = _client()
    r = c.get("/v1/serviceability", params={"pincode": "abc"})
    assert r.status_code == 400
