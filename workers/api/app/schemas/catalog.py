"""Catalog + quote DTOs (wire contracts only — never DB models). All money integer paise."""
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

SkuId = Literal["refill", "container"]


class SkuOut(BaseModel):
    id: SkuId
    price_paise: int = Field(ge=0)


class CatalogOut(BaseModel):
    skus: list[SkuOut]
    deposit_per_jar: int = Field(ge=0)
    cap_charge: int = Field(ge=0)
    hours: str = ""
    holidays: list[str] = Field(default_factory=list)


class QuoteItemIn(BaseModel):
    sku: SkuId
    qty: int = Field(ge=0, le=10)


class QuoteIn(BaseModel):
    items: list[QuoteItemIn] = Field(min_length=1)
    e: int = Field(ge=0)
    address_id: str = Field(min_length=1)
    window_start: str = Field(min_length=1)

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


class QuoteOut(BaseModel):
    water_bill: int = Field(ge=0)
    deposit_due: int = Field(ge=0)
    cap_note: str
    total: int = Field(ge=0)
    quote_hash: str = Field(min_length=1)
    expires_at: datetime  # UTC, now+15min
