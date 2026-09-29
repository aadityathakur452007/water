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
    upi_provider: str = "fake"  # fake|real (razorpay-shaped HMAC skeleton)
    upi_key_id: str | None = None
    upi_key_secret: str | None = None
    upi_webhook_secret: str | None = None
    agency_upi_vpa: str | None = None  # required before payee lock enforces
