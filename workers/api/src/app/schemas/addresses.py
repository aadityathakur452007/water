"""Address DTOs (wire contracts only — never DB models).

Pydantic is the trust boundary (ssdlc): GPS sanity + pincode allowlist enforced
here AND re-checked in AddressRepo (defense in depth for direct repo callers).
Money: no money fields on addresses. Contract §4.3.
"""

from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

AddressType = Literal["home", "office"]

_PINCODE_PATTERN = r"^[1-9]\d{5}$"


class AddressIn(BaseModel):
    type: AddressType
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    accuracy_m: float | None = Field(default=None, ge=0)
    place_id: str | None = None
    formatted: str | None = None
    landmark: str | None = None
    label: str | None = None
    pincode: str = Field(pattern=_PINCODE_PATTERN)
    lift_flag: bool = False
    # 011_port: full address format (all optional, back-compat; phone stored
    # as-given, no format gate so existing +91 values keep working).
    # F1 caps (ADR-056): 500 chars like complaints/vendor notes — unbounded
    # TEXT is a storage/abuse hole up to the 1MB body cap.
    house: str | None = Field(default=None, max_length=500)
    street: str | None = Field(default=None, max_length=500)
    area: str | None = Field(default=None, max_length=500)
    phone: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def _reject_null_island(self):
        if self.lat == 0 and self.lng == 0:
            raise ValueError("GPS fix required — (0,0) is not a valid location")
        return self

    @field_validator("pincode")
    @classmethod
    def _strip_pincode(cls, v: str) -> str:
        return v.strip()


class AddressPatch(BaseModel):
    type: AddressType | None = None
    lat: float | None = Field(default=None, ge=-90, le=90)
    lng: float | None = Field(default=None, ge=-180, le=180)
    accuracy_m: float | None = Field(default=None, ge=0)
    place_id: str | None = None
    formatted: str | None = None
    landmark: str | None = None
    label: str | None = None
    pincode: str | None = Field(default=None, pattern=_PINCODE_PATTERN)
    lift_flag: bool | None = None
    house: str | None = Field(default=None, max_length=500)
    street: str | None = Field(default=None, max_length=500)
    area: str | None = Field(default=None, max_length=500)
    phone: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def _reject_null_island(self):
        if self.lat is not None and self.lng is not None:
            if self.lat == 0 and self.lng == 0:
                raise ValueError("GPS fix required — (0,0) is not a valid location")
        return self


class AddressOut(BaseModel):
    id: str
    type: AddressType
    label: str | None = None
    lat: float
    lng: float
    place_id: str | None = None
    formatted: str | None = None
    landmark: str | None = None
    pincode: str
    lift_flag: bool = False
    serviceable: bool = True
    needs_pin_confirm: bool = False
    created_at: str | None = None
    house: str | None = None
    street: str | None = None
    area: str | None = None
    phone: str | None = None
