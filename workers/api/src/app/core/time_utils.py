"""Shared UTC/IST time, date-parsing, expiry, and SLA helpers."""

from __future__ import annotations

import datetime as _dt


def utc_now() -> _dt.datetime:
    """Return the current timezone-aware UTC datetime."""
    return _dt.datetime.now(_dt.timezone.utc)


def utc_now_iso() -> str:
    """Return the current UTC timestamp as an ISO-8601 string."""
    return utc_now().isoformat()


def utc_today_iso() -> str:
    """Return the current UTC date as YYYY-MM-DD."""
    return utc_now().date().isoformat()


def ist_today_iso() -> str:
    """Return the current IST (UTC+05:30) date as YYYY-MM-DD."""
    return (utc_now() + _dt.timedelta(hours=5, minutes=30)).date().isoformat()


def parse_utc_dt(value: object) -> _dt.datetime | None:
    """Parse a datetime or ISO string into a timezone-aware UTC datetime."""
    if isinstance(value, _dt.datetime):
        dt = value
    elif isinstance(value, str):
        try:
            dt = _dt.datetime.fromisoformat(value)
        except ValueError:
            return None
    else:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=_dt.timezone.utc)
    return dt.astimezone(_dt.timezone.utc)


def is_expired(iso_ts: object) -> bool:
    """Return True when ``iso_ts`` is missing, unparseable, or at/before now."""
    dt = parse_utc_dt(iso_ts)
    if dt is None:
        return True
    return dt <= utc_now()


def sla_due(from_day: _dt.date | None = None, working_days: int = 10) -> str:
    """Add ``working_days`` skipping Sundays and return YYYY-MM-DD."""
    d = from_day or utc_now().date()
    added = 0
    while added < working_days:
        d += _dt.timedelta(days=1)
        if d.weekday() == 6:
            continue
        added += 1
    return d.isoformat()
