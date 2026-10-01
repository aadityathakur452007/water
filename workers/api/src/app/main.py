"""App factory (Factory pattern). Thin composition only — no business logic here.

B2 owns app.api.v1.catalog and app.api.v1.quotes: each must expose `router`
(an APIRouter with bare paths, e.g. @router.get("/catalog")); this factory
mounts them under the /v1 contract prefix.
"""

from fastapi import FastAPI

from app.api.deps import trace_middleware
from app.api.middleware import (
    body_cap_middleware,
    configure_cors,
    security_headers_middleware,
    throttle_middleware,
)
from app.api.v1.addresses import router as addresses_router
from app.api.v1.admin import router as admin_router
from app.api.v1.auth import router as auth_router
from app.api.v1.catalog import router as catalog_router
from app.api.v1.complaints import router as complaints_router
from app.api.v1.devices import router as devices_router
from app.api.v1.orders import router as orders_router
from app.api.v1.payments import router as payments_router
from app.api.v1.quotes import router as quotes_router
from app.api.v1.ratings import router as ratings_router
from app.api.v1.returns import router as returns_router
from app.api.v1.subscriptions import router as subscriptions_router
from app.api.v1.vendor import router as vendor_router
from app.core.errors import register_exception_handlers


def create_app() -> FastAPI:
    app = FastAPI(title="Shodasha API v1")
    app.middleware("http")(trace_middleware)
    app.middleware("http")(security_headers_middleware)
    app.middleware("http")(body_cap_middleware)
    app.middleware("http")(throttle_middleware)
    configure_cors(app)
    register_exception_handlers(app)
    app.include_router(catalog_router, prefix="/v1")
    app.include_router(quotes_router, prefix="/v1")
    app.include_router(addresses_router, prefix="/v1")
    app.include_router(orders_router, prefix="/v1")
    app.include_router(auth_router, prefix="/v1")
    app.include_router(payments_router, prefix="/v1")
    app.include_router(vendor_router, prefix="/v1")
    app.include_router(subscriptions_router, prefix="/v1")
    app.include_router(returns_router, prefix="/v1")
    app.include_router(complaints_router, prefix="/v1")
    app.include_router(ratings_router, prefix="/v1")
    app.include_router(devices_router, prefix="/v1")
    app.include_router(admin_router, prefix="/v1")

    @app.get("/health")
    def health() -> dict:
        return {"status": "ok"}

    return app


app = create_app()
