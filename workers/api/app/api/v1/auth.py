"""Auth routes: Pydantic boundary -> AuthService -> 2xx (contract §4.1).

Bare ``router`` (mounted under /v1 by the app factory/integrator — same pattern
as quotes.py/orders.py). DTOs live here (no schemas/auth.py: the 9-file slice
keeps the wire contract next to its only consumer). Pydantic failures -> 400
VALIDATION via B1's handler; service errors map via their code/status attrs.

Suspended GET /auth/me -> 200 + restrictions (contract §4.1 C1/C2); PATCH and
all other writes die in require_active_user (403 FORBIDDEN).
"""

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field

from app.adapters.firebase import get_verifier
from app.api.auth_deps import get_current_user, require_active_user
from app.api.deps import get_db
from app.services.auth_service import AuthService

router = APIRouter(tags=["auth"])


class DeviceIn(BaseModel):
    id: str = Field(min_length=1, max_length=128)
    integrity: str | None = Field(default=None, max_length=256)


class OtpStartIn(BaseModel):
    phone: str = Field(min_length=10, max_length=16)


class OtpVerifyIn(BaseModel):
    firebase_id_token: str = Field(min_length=1)
    device: DeviceIn


class RefreshIn(BaseModel):
    refresh_token: str = Field(min_length=1)
    device: DeviceIn


class LogoutIn(BaseModel):
    revoke_all: bool = False
    device_id: str | None = Field(default=None, max_length=128)


class MePatchIn(BaseModel):
    name: str | None = Field(default=None, max_length=80)
    language: str | None = Field(default=None, pattern=r"^[a-z]{2}(-[A-Z]{2})?$")


def _service(conn=Depends(get_db), verifier=Depends(get_verifier)) -> AuthService:
    return AuthService(conn, verifier)


@router.post("/auth/otp/start", status_code=202)
def otp_start(payload: OtpStartIn, request: Request, svc: AuthService = Depends(_service)):
    ip = request.client.host if request.client else "unknown"
    return svc.otp_start(payload.phone, ip)


@router.post("/auth/otp/verify")
def otp_verify(payload: OtpVerifyIn, svc: AuthService = Depends(_service)):
    return svc.otp_verify(payload.firebase_id_token, payload.device.model_dump())


@router.post("/auth/refresh")
def refresh(payload: RefreshIn, svc: AuthService = Depends(_service)):
    return svc.refresh(payload.refresh_token, payload.device.id)


@router.post("/auth/logout")
def logout(
    payload: LogoutIn,
    user: dict = Depends(get_current_user),
    svc: AuthService = Depends(_service),
):
    return svc.logout(
        session_id=user["session_id"],
        family_id=user["family_id"],
        user_id=user["id"],
        device_id=payload.device_id or user["device_fp"],
        revoke_all=payload.revoke_all,
    )


@router.get("/auth/me")
def get_me(user: dict = Depends(get_current_user), svc: AuthService = Depends(_service)):
    return svc.me(user["id"])


@router.patch("/auth/me")
def patch_me(
    payload: MePatchIn,
    user: dict = Depends(require_active_user),
    svc: AuthService = Depends(_service),
):
    return svc.update_me(user["id"], name=payload.name, language=payload.language)
