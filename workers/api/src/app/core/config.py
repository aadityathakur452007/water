"""Central settings (Singleton via deps.get_settings).

All money fields are integer paise (contract §0). pydantic-settings fails fast
on missing/invalid values. Provider credentials are optional until wired:
Firebase project activates RealVerifier; UPI keys activate the real provider
path (webhook secret gates verify_webhook); agency VPA gates the payee lock.
"""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_env: str = "local"
    database_path: str = "./data/shodasha.db"
    rate_refill_paise: int = 2800
    rate_container_paise: int = 3000
    deposit_per_jar_paise: int = 15000
    cap_charge_paise: int = 300
    quote_ttl_minutes: int = 15
    firebase_project_id: str | None = None
    dev_auth: bool = False  # DEV_AUTH=1: raw-code admin login for local dev only
    upi_provider: str = "fake"  # fake|razorpay (RealUpiProvider REST Orders API)
    upi_key_id: str | None = None
    upi_key_secret: str | None = None
    upi_webhook_secret: str | None = None
    agency_upi_vpa: str | None = None  # required before payee lock enforces
    otp_provider: str = "firebase"  # firebase|fast2sms (server-generated codes)
    fast2sms_api_key: str | None = None  # worker secret FAST2SMS_API_KEY
    fast2sms_sender_id: str | None = None  # DLT-approved header (default SHODASHA)
    fast2sms_entity_id: str | None = None  # DLT principal-entity id (dashboard link)
    cors_origins: str = ""  # comma-separated allowlist (CORS_ORIGINS); empty = deny credentialed cross-origin
    body_max_bytes: int = 1_000_000  # JSON body cap → 413 (ssdlc Phase 6)
    throttle_anon_per_min: int = 120  # anon GETs (catalog/windows/serviceability) per IP/min → 429

    @property
    def allowed_origins(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]
