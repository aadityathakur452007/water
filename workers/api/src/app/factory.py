"""Surface-aware app factory (045 worker split).

One Python codebase, three Workers:

    water        -> create_app("customer")   donor app + cron
    water-ops    -> create_app("ops")        vendor + rider apps
    water-admin  -> create_app("admin")      admin web BFF

``create_app("all")`` (the default) mounts every router, which is what local
uvicorn and the 470-test suite use — so pytest behavior is unchanged. Entry
points import this module directly, never ``app.main``, to avoid building a
second full app at import time.
"""

from fastapi import FastAPI

from app.api.deps import trace_middleware
from app.api.health import router as health_router
from app.api.middleware import (
    body_cap_middleware,
    configure_cors,
    security_headers_middleware,
    throttle_middleware,
)
from app.api.v1.addresses import router as addresses_router
from app.api.v1.admin import router as admin_router
from app.api.v1.auth import (
    admin_router as auth_admin_router,
    customer_router as auth_customer_router,
    ops_router as auth_ops_router,
    shared_router as auth_shared_router,
)
from app.api.v1.catalog import router as catalog_router
from app.api.v1.complaints import router as complaints_router
from app.api.v1.devices import router as devices_router
from app.api.v1.orders import router as orders_router
from app.api.v1.payments import admin_router as payments_admin_router
from app.api.v1.payments import router as payments_router
from app.api.v1.quotes import router as quotes_router
from app.api.v1.ratings import router as ratings_router
from app.api.v1.returns import ops_router as returns_ops_router
from app.api.v1.returns import router as returns_router
from app.api.v1.rider import router as rider_router
from app.api.v1.subscriptions import router as subscriptions_router
from app.api.v1.vendor import router as vendor_router
from app.core.errors import register_exception_handlers

SURFACES = ("all", "customer", "ops", "admin")

_V1 = "/v1"


def _mount_customer(app: FastAPI) -> None:
    """Donor app surface: customer reads/writes + Razorpay webhook."""
    app.include_router(auth_customer_router, prefix=_V1)
    app.include_router(catalog_router, prefix=_V1)
    app.include_router(quotes_router, prefix=_V1)
    app.include_router(addresses_router, prefix=_V1)
    app.include_router(orders_router, prefix=_V1)
    app.include_router(payments_router, prefix=_V1)
    app.include_router(subscriptions_router, prefix=_V1)
    app.include_router(returns_router, prefix=_V1)
    app.include_router(complaints_router, prefix=_V1)
    app.include_router(ratings_router, prefix=_V1)
    app.include_router(devices_router, prefix=_V1)


def _mount_ops(app: FastAPI) -> None:
    """Vendor + rider surface (`water-ops`)."""
    app.include_router(auth_ops_router, prefix=_V1)
    app.include_router(vendor_router, prefix=_V1)
    app.include_router(rider_router, prefix=_V1)
    app.include_router(returns_ops_router, prefix=_V1)


def _mount_admin(app: FastAPI) -> None:
    """Admin web surface (`water-admin`)."""
    app.include_router(auth_admin_router, prefix=_V1)
    app.include_router(admin_router, prefix=_V1)
    app.include_router(payments_admin_router, prefix=_V1)


def create_app(surface: str = "all") -> FastAPI:
    if surface not in SURFACES:
        raise ValueError(f"Unknown surface {surface!r}; expected one of {SURFACES}.")
    app = FastAPI(title="Shodasha API v1")
    # Last added runs outermost. Trace is added last (before CORS) so throttle
    # and body-cap rejections still get a trace id and a structured log line.
    app.middleware("http")(security_headers_middleware)
    app.middleware("http")(body_cap_middleware)
    app.middleware("http")(throttle_middleware)
    app.middleware("http")(trace_middleware)
    configure_cors(app)
    register_exception_handlers(app)

    # refresh/logout/me exist on every surface: sessions live in shared D1.
    app.include_router(auth_shared_router, prefix=_V1)
    if surface in ("all", "customer"):
        _mount_customer(app)
    if surface in ("all", "ops"):
        _mount_ops(app)
    if surface in ("all", "admin"):
        _mount_admin(app)
    app.include_router(health_router)

    return app
