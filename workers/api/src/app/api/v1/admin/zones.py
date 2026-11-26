from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Request

from app.api.auth_deps import get_current_user, require_role  # noqa: F401
from app.api.caching import cached
from app.api.deps import get_db_conn
from app.core.errors import NotFoundError
from app.db import WRITE_LOCK
from app.services.dispatch_service import (
    CustodyBlockedError,
    ensure_profile,
)
from app.api.v1.admin._common import *  # noqa: F401, F403

router = APIRouter(tags=["admin"])

@router.get("/admin/zones")
async def zone_list(request: Request, conn=Depends(get_db_conn), user=Admin):
    rows = (await conn.execute(
        """SELECT z.id, z.name, z.pincodes, z.polygon, z.active,
                  COUNT(vz.vendor_id) AS vendor_count
           FROM zones z
           LEFT JOIN vendor_zones vz ON z.id = vz.zone_id
           GROUP BY z.id
           ORDER BY z.name
           LIMIT 200"""
    )).fetchall()
    # Phase 8 §8.5: auth still required; admin bytes must never enter a
    # shared cache, so private=True emits `private, no-store`.
    return cached({"data": [dict(r) for r in rows]}, request, private=True)


@router.post("/admin/zones", status_code=201)
async def zone_create(payload: ZoneCreateIn, conn=Depends(get_db_conn), user=Admin):
    import re
    name = payload.name.strip()
    zid = (payload.id.strip() if payload.id and payload.id.strip() else None)
    if not zid:
        slug = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
        zid = f"zone_{slug}" if slug else f"zone_{uuid.uuid4().hex[:8]}"

    pins = ", ".join(p.strip() for p in payload.pincodes.split(",") if p.strip())

    with WRITE_LOCK:
        existing = (await conn.execute("SELECT id FROM zones WHERE id = ?", (zid,))).fetchone()
        if existing:
            zid = f"{zid}_{uuid.uuid4().hex[:4]}"
        await conn.execute(
            "INSERT INTO zones(id, name, pincodes, polygon, active) VALUES (?, ?, ?, ?, 1)",
            (zid, name, pins, payload.polygon),
        )
        await _audit(conn, user, "zone.create", "zones", zid, "", {"name": name, "pincodes": pins})
        conn.commit()
    return {"id": zid, "name": name, "pincodes": pins, "polygon": payload.polygon, "active": 1, "vendor_count": 0}


@router.patch("/admin/zones/{zone_id}")
async def zone_patch(zone_id: str, payload: ZonePatchIn, conn=Depends(get_db_conn), user=Admin):
    with WRITE_LOCK:
        row = (await conn.execute("SELECT id, name, pincodes, polygon, active FROM zones WHERE id = ?", (zone_id,))).fetchone()
        if row is None:
            raise NotFoundError(message="Zone not found.", details={"id": zone_id})
        before = dict(row)
        name = payload.name.strip() if payload.name is not None else row["name"]
        pins = (
            ", ".join(p.strip() for p in payload.pincodes.split(",") if p.strip())
            if payload.pincodes is not None
            else row["pincodes"]
        )
        active = payload.active if payload.active is not None else row["active"]
        await conn.execute(
            "UPDATE zones SET name = ?, pincodes = ?, active = ? WHERE id = ?",
            (name, pins, active, zone_id),
        )
        after = {"name": name, "pincodes": pins, "active": active}
        await _audit(conn, user, "zone.patch", "zones", zone_id, before, after)
        conn.commit()
    return {"id": zone_id, "name": name, "pincodes": pins, "active": active}


@router.post("/admin/zones/{zone_id}/vendors/attach")
async def zone_attach(zone_id: str, payload: AttachIn, conn=Depends(get_db_conn), user=Admin):
    with WRITE_LOCK:
        if (await conn.execute("SELECT id FROM zones WHERE id = ?", (zone_id,))).fetchone() is None:
            raise NotFoundError(message="Zone not found.", details={"id": zone_id})
        await conn.execute("INSERT OR IGNORE INTO vendor_zones(vendor_id, zone_id, priority)"
                     " VALUES (?, ?, ?)", (payload.vendor_id, zone_id, int(payload.priority)))
        await _audit(conn, user, "zone.attach", "zones", zone_id, "", {"vendor_id": payload.vendor_id})
        conn.commit()
    return {"zone_id": zone_id, "vendor_id": payload.vendor_id}


@router.post("/admin/zones/{zone_id}/vendors/{vendor_id}/detach")
async def zone_detach(zone_id: str, vendor_id: str, payload: DetachIn,
                conn=Depends(get_db_conn), user=Admin):
    with WRITE_LOCK:
        prof = await ensure_profile(conn, vendor_id)
        if int(prof.get("in_hand", 0)) != 0:
            raise CustodyBlockedError(
                message="Vendor still holds agency cash. Complete handover before detach.",
                details={"vendor_id": vendor_id, "in_hand": int(prof["in_hand"])})
        cur = await conn.execute("DELETE FROM vendor_zones WHERE vendor_id = ? AND zone_id = ?",
                           (vendor_id, zone_id))
        if cur.rowcount == 0:
            raise NotFoundError(message="Vendor is not attached to this zone.",
                                details={"zone_id": zone_id, "vendor_id": vendor_id})
        await _audit(conn, user, "zone.detach", "zones", zone_id,
               {"vendor_id": vendor_id}, payload.reason)
        conn.commit()
    return {"zone_id": zone_id, "vendor_id": vendor_id, "detached": True}


# -- money: ledger adjust, write-off, invoices stub, reconciliation -------------

