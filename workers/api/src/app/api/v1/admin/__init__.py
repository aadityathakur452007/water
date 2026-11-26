"""Admin router package: dispatch, vendors, zones, finance, support, users, system."""

from fastapi import APIRouter

from app.api.auth_deps import get_current_user, require_role  # noqa: F401
from app.api.v1.admin._common import Admin, ReassignCustomersIn, SuspendIn  # noqa: F401
from app.api.v1.admin.finance import router as _finance_router
from app.api.v1.admin.ops_support import router as _ops_support_router
from app.api.v1.admin.orders import router as _orders_router
from app.api.v1.admin.system import (  # noqa: F401
    _METRICS_TTL_S,
    _metrics_cached,
    reset_metrics_cache,
    router as _system_router,
)
from app.repositories.admin_read_repo import AdminReadRepo  # noqa: F401
from app.api.v1.admin.users import (  # noqa: F401
    admin_suspend_user,
    admin_unsuspend_user,
    router as _users_router,
)
from app.api.v1.admin.vendors import (  # noqa: F401
    get_orphan_customers,
    reassign_vendor_customers,
    router as _vendors_router,
)
from app.api.v1.admin.zones import router as _zones_router

router = APIRouter(tags=["admin"])
for _sub in (
    _orders_router,
    _vendors_router,
    _zones_router,
    _finance_router,
    _ops_support_router,
    _system_router,
    _users_router,
):
    router.include_router(_sub)
