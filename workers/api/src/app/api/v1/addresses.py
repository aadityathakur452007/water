"""Address routes: Pydantic boundary -> service rules -> AddressRepo -> 2xx.

Bare `router` (mounted under /v1 by the app factory — same pattern as
quotes.py). Every endpoint is owner-scoped behind get_current_user (C1 owns
app.api.auth_deps; the ImportError fallback below is slice-2 scaffolding only
and raises 401 until C1 lands — this file never defines auth itself).

IDOR: repo miss -> NotFoundError (same shape as not-found, no oracle §3).
Pydantic boundary failures -> 400 VALIDATION via B1's handler. Active-order
edit/delete blocks -> 409 STATE_CONFLICT from the repo.
"""

from fastapi import APIRouter, Depends, Response

from app.api.deps import get_db_conn
from app.core.errors import NotFoundError

try:  # C1 owns app.api.auth_deps; fallback 401s until it lands.
    from app.api.auth_deps import get_current_user  # type: ignore
except ImportError:  # pragma: no cover

    async def get_current_user():  # type: ignore
        from fastapi import HTTPException

        raise HTTPException(status_code=401, detail="Unauthorized")


from app.repositories.address_repo import AddressRepo  # noqa: E402
from app.schemas.addresses import AddressIn, AddressOut, AddressPatch  # noqa: E402
from app.services import address_service  # noqa: E402

router = APIRouter(tags=["addresses"])


def _user_id(user) -> str:
    if isinstance(user, dict):
        return str(user.get("id") or user.get("user_id") or user.get("sub"))
    return str(getattr(user, "id", getattr(user, "user_id", getattr(user, "sub", user))))


def _to_out(row: dict, needs_pin_confirm: bool = False) -> AddressOut:
    return AddressOut(
        id=str(row["id"]),
        type=row["type"],
        label=row.get("label"),
        lat=float(row["lat"]),
        lng=float(row["lng"]),
        place_id=row.get("place_id"),
        formatted=row.get("formatted"),
        landmark=row.get("landmark"),
        pincode=str(row["pincode"]),
        lift_flag=bool(row.get("lift_flag")),
        serviceable=bool(row.get("serviceable", 1)),
        needs_pin_confirm=needs_pin_confirm,
        created_at=row.get("created_at"),
    )


@router.get("/addresses", response_model=list[AddressOut])
async def list_addresses(user=Depends(get_current_user), conn=Depends(get_db_conn)):
    rows = await AddressRepo(conn).list_by_user(_user_id(user))
    return [_to_out(r) for r in rows]


@router.post("/addresses", response_model=AddressOut, status_code=201)
async def create_address(payload: AddressIn, user=Depends(get_current_user), conn=Depends(get_db_conn)):
    address_service.verify_place_id_stub(payload.place_id)
    serviceable = address_service.serviceability(payload.pincode)
    address_service.lookup_zone(payload.pincode, payload.lat, payload.lng)  # STUB -> None
    row = await AddressRepo(conn).create(_user_id(user), payload, serviceable=serviceable)
    return _to_out(row, address_service.needs_pin_confirm(payload.accuracy_m))


@router.patch("/addresses/{addr_id}", response_model=AddressOut)
async def update_address(addr_id: str, payload: AddressPatch, user=Depends(get_current_user), conn=Depends(get_db_conn)):
    repo = AddressRepo(conn)
    if await repo.get_owned(addr_id, _user_id(user)) is None:
        raise NotFoundError("Address not found", {"id": addr_id})
    data = payload.model_dump(exclude_unset=True)
    serviceable = address_service.serviceability(data["pincode"]) if data.get("pincode") else None
    row = await repo.update_owned(addr_id, _user_id(user), data, serviceable=serviceable)
    if row is None:  # raced delete
        raise NotFoundError("Address not found", {"id": addr_id})
    return _to_out(row, address_service.needs_pin_confirm(data.get("accuracy_m")))


@router.delete("/addresses/{addr_id}", status_code=204)
async def delete_address(addr_id: str, user=Depends(get_current_user), conn=Depends(get_db_conn)):
    ok = await AddressRepo(conn).delete_owned(addr_id, _user_id(user))
    if not ok:
        raise NotFoundError("Address not found", {"id": addr_id})
    return Response(status_code=204)
