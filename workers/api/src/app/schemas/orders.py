"""Order DTOs (wire contracts only — never DB models). All money integer paise."""
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

SkuId = Literal["refill", "container"]
PaymentMode = Literal["upi", "cod"]


class OrderItemIn(BaseModel):
    sku: SkuId
    qty: int = Field(ge=0, le=10)


class OrderIn(BaseModel):
    items: list[OrderItemIn] = Field(min_length=1)
    e: int = Field(ge=0)
    address_id: str = Field(min_length=1)
    window_start: str = Field(min_length=1)
    quote_hash: str = Field(min_length=1)
    quote_total: int = Field(ge=0)  # client echo; server recomputes, mismatch -> 409
    quote_rate_version: str = Field(min_length=1)
    quote_expires_at: datetime
    payment_mode: PaymentMode = "cod"

    @model_validator(mode="after")
    def _check_empties_and_minimum(self):
        n = sum(i.qty for i in self.items)
        if n < 1:
            raise ValueError("at least 1 jar required")
        if self.e > n:
            raise ValueError("e (empties) must be <= total jars N")
        return self

    @field_validator("address_id", "window_start")
    @classmethod
    def _not_blank(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("must not be blank")
        return v


class OrderOut(BaseModel):
    id: str
    user_id: str
    address_id: str
    items: list[dict]
    n: int
    e: int
    water_bill: int
    deposit_due: int
    cap_charge: int
    total: int
    payment_mode: str
    payment_status: str
    state: str
    window_start: str
    window_end: str = ""
    quote_hash: str
    quote_rate_version: str
    created_at: str


class OrderDetailOut(OrderOut):
    tracker: dict = Field(default_factory=dict)  # 4-step tracker + current state
    rider: dict | None = None  # {name, call} once assigned; None before
    bill: dict = Field(default_factory=dict)
    events: list[dict] = Field(default_factory=list)


class OrderListOut(BaseModel):
    data: list[OrderOut]
    next_cursor: str | None = None


class CancelIn(BaseModel):
    reason: str = Field(min_length=1, max_length=500)

    @field_validator("reason")
    @classmethod
    def _strip(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("must not be blank")
        return v


class CancelOut(BaseModel):
    order_id: str
    state: str
    bill_total: int
    deposit_reversed: int
    refund: dict | None = None


class RescheduleIn(BaseModel):
    window_start: str = Field(min_length=1)

    @field_validator("window_start")
    @classmethod
    def _strip(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("must not be blank")
        return v
