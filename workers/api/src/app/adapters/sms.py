"""SMS OTP provider adapter (Adapter + Strategy pattern) — server-OTP slice.

Mirrors ``adapters/upi.py``: same factory shape (``get_sms_provider``), same
error contract (``AppError`` subclasses → central envelope), same env bridge
(worker env wins, process env second, ``.env``-backed Settings third).

Strategy note: Firebase-verify vs server-code is a Strategy — ``AuthService``
picks the path by ``OTP_PROVIDER`` (``firebase`` default = current behavior,
``fast2sms`` = server codes over the Fast2SMS DLT route, ``textbee`` =
server codes over the user's own Android phone + SIM via the TextBee cloud
API — no DLT portal, no per-SMS bill, 300 msgs/month free tier).
``FakeSmsProvider`` is the test/dev double (log-only, never hits network).
"""

from __future__ import annotations

import logging

import httpx

from app.core.worker_env import env_get as _worker_env_get

from app.core.errors import AppError

log = logging.getLogger(__name__)


class SmsUpstreamError(AppError):
    code = "UPSTREAM_FAIL"
    status_code = 502


FAST2SMS_URL = "https://www.fast2sms.com/dev/bulkV2"
TEXTBEE_URL = "https://api.textbee.dev/api/v1/gateway/send-sms"


def _setting(env_name: str, default=None):
    """Worker env wins, process env second, .env-backed Settings third.

    Same bridge as upi.py/firewall: adapters must never read os.environ alone
    (empty on Workers; local secrets live in the gitignored .env that only
    pydantic-settings loads).
    """
    direct = _worker_env_get(env_name)
    if direct not in (None, ""):
        return direct
    try:
        from app.core.config import Settings  # noqa: PLC0415 (lazy, mirrors upi.py)

        value = getattr(Settings(), env_name.lower(), None)
        return value if value not in (None, "") else default
    except Exception:
        return default


def otp_provider() -> str:
    """Active OTP channel: ``firebase`` (default) or ``fast2sms``."""
    return str(_setting("OTP_PROVIDER", "firebase") or "firebase").lower()


class SmsProvider:
    """Interface: send_otp(phone_e164, code) -> {"provider": ..., "to_masked": ...}."""

    def send_otp(self, phone: str, code: str) -> dict:  # pragma: no cover - interface
        raise NotImplementedError


class FakeSmsProvider(SmsProvider):
    """Test/dev double: logs the code, sends nothing (no DLT, no wallet)."""

    def __init__(self):
        self.sent: list[dict] = []

    def send_otp(self, phone: str, code: str) -> dict:
        log.info("sms(fake) otp to=%s code_len=%d", phone, len(code))
        self.sent.append({"phone": phone, "code": code})
        return {"provider": "fake", "to_masked": phone}


class Fast2SmsProvider(SmsProvider):
    """Real Fast2SMS DLT route (transactional OTP, DND-safe, 24x7).

    Requires aproved DLT sender header + OTP template on the account, plus
    wallet balance. ``message`` is composed server-side and must match the
    approved template text (with the code in the variable slot).
    """

    def __init__(self, api_key: str | None = None, sender_id: str | None = None):
        self._key = api_key or _setting("FAST2SMS_API_KEY")
        self._sender = sender_id or _setting("FAST2SMS_SENDER_ID", "SHODASHA")
        if not self._key:
            raise SmsUpstreamError("SMS provider not configured.", {"retryable": False})

    def send_otp(self, phone: str, code: str) -> dict:
        digits = "".join(c for c in phone if c.isdigit())[-10:]
        try:
            resp = httpx.post(
                FAST2SMS_URL,
                headers={"authorization": str(self._key)},
                params={
                    "sender_id": str(self._sender),
                    "message": f"Your Shodasha login code is {code}.",
                    "language": "english",
                    "route": "dlt",
                    "numbers": digits,
                },
                timeout=15,
            )
        except Exception as e:
            raise SmsUpstreamError("SMS provider unreachable.", {"retryable": True}) from e
        if resp.status_code != 200:
            raise SmsUpstreamError(
                "SMS provider rejected the request.",
                {"retryable": True, "status": resp.status_code},
            )
        return {"provider": "fast2sms", "to_masked": phone}


def get_sms_provider() -> SmsProvider:
    """Factory: ``fast2sms``/``textbee`` (+ key) → real; anything else → fake.

    The fake is the safe default: no network, no wallet, no DLT needed.
    """
    name = otp_provider()
    if name == "fast2sms":
        return Fast2SmsProvider()
    if name == "textbee":
        return TextBeeProvider()
    return FakeSmsProvider()


class TextBeeProvider(SmsProvider):
    """User's own Android phone as the sender (TextBee cloud API, no DLT).

    Setup (user-side, once): install the TextBee app on the gateway phone,
    link the device (scan QR), create an API key. The phone must stay on,
    charged, and online — phone off means no OTPs go out. Free tier: 300
    msgs/month, 50/day, 1 device. Sender shown is the SIM's own number.
    """

    def __init__(self, api_key: str | None = None, device_id: str | None = None):
        self._key = api_key or _setting("TEXTBEE_API_KEY")
        self._device = device_id or _setting("TEXTBEE_DEVICE_ID")
        if not self._key:
            raise SmsUpstreamError("SMS provider not configured.", {"retryable": False})

    def send_otp(self, phone: str, code: str) -> dict:
        body: dict = {"recipients": [phone], "message": f"Your Shodasha login code is {code}."}
        if self._device:
            body["deviceId"] = self._device
        try:
            resp = httpx.post(
                TEXTBEE_URL,
                headers={"x-api-key": str(self._key), "Content-Type": "application/json"},
                json=body,
                timeout=15,
            )
        except Exception as e:
            raise SmsUpstreamError("SMS provider unreachable.", {"retryable": True}) from e
        if resp.status_code not in (200, 201):
            raise SmsUpstreamError(
                "SMS provider rejected the request.",
                {"retryable": True, "status": resp.status_code},
            )
        return {"provider": "textbee", "to_masked": phone}
