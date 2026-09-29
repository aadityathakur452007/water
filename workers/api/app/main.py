"""App factory (Factory pattern). Thin composition only — no business logic here.

B2 owns app.api.v1.catalog and app.api.v1.quotes: each must expose `router`
(an APIRouter with bare paths, e.g. @router.get("/catalog")); this factory
mounts them under the /v1 contract prefix.
"""

from fastapi import FastAPI

from app.api.deps import trace_middleware
from app.api.v1.catalog import router as catalog_router
from app.api.v1.quotes import router as quotes_router
from app.core.errors import register_exception_handlers


def create_app() -> FastAPI:
    app = FastAPI(title="Shodasha API v1")
    app.middleware("http")(trace_middleware)
    register_exception_handlers(app)
    app.include_router(catalog_router, prefix="/v1")
    app.include_router(quotes_router, prefix="/v1")

    @app.get("/health")
    def health() -> dict:
        return {"status": "ok"}

    return app


app = create_app()
