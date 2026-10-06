"""Central error hierarchy + FastAPI handlers (contract §0).

Every error returns the envelope {error: {code, message, details, trace_id}}.
Trace id comes from the X-Trace-Id header (echoed) or is generated. Unknown
errors map to a generic 500 — no stack traces, SQL, or secrets leak to clients.
"""

import uuid

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

TRACE_HEADER = "X-Trace-Id"


def get_trace_id(request: Request) -> str:
    header_trace = request.headers.get(TRACE_HEADER)
    if header_trace:
        return header_trace
    state_trace = getattr(request.state, "trace_id", None)
    if state_trace:
        return state_trace
    return uuid.uuid4().hex[:16]


def error_envelope(code: str, message: str, details: dict | None, trace_id: str) -> dict:
    return {"error": {"code": code, "message": message, "details": details or {}, "trace_id": trace_id}}


class AppError(Exception):
    code = "SERVER"
    status_code = 500

    def __init__(self, message: str = "Internal error", details: dict | None = None):
        super().__init__(message)
        self.message = message
        self.details = details or {}


class ValidationError(AppError):
    code = "VALIDATION"
    status_code = 400


class NotFoundError(AppError):
    code = "NOT_FOUND"
    status_code = 404


class ConflictError(AppError):
    code = "STATE_CONFLICT"
    status_code = 409


class RateLimitedError(AppError):
    code = "RATE_LIMITED"
    status_code = 429


async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
    trace_id = get_trace_id(request)
    response = JSONResponse(
        status_code=exc.status_code,
        content=error_envelope(exc.code, exc.message, exc.details, trace_id),
    )
    # Phase 8 §8.4: auth 429s carry Retry-After like the edge throttle —
    # clients back off instead of hammering the D1 single writer.
    if exc.code == "RATE_LIMITED":
        retry = (exc.details or {}).get("retry_after_s")
        if retry is not None:
            response.headers["Retry-After"] = str(retry)
    return response


_HTTP_STATUS_TO_CODE = {
    400: "VALIDATION",
    401: "UNAUTH",
    403: "FORBIDDEN",
    404: "NOT_FOUND",
    409: "STATE_CONFLICT",
    429: "RATE_LIMITED",
}


async def http_exception_handler(request: Request, exc: StarletteHTTPException) -> JSONResponse:
    trace_id = get_trace_id(request)
    code = _HTTP_STATUS_TO_CODE.get(exc.status_code, "SERVER")
    return JSONResponse(
        status_code=exc.status_code,
        content=error_envelope(code, str(exc.detail), {}, trace_id),
    )


async def request_validation_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    trace_id = get_trace_id(request)
    errors = [{"loc": list(e.get("loc", [])), "msg": e.get("msg"), "type": e.get("type")} for e in exc.errors()]
    return JSONResponse(
        status_code=400,
        content=error_envelope("VALIDATION", "Invalid request", {"errors": errors}, trace_id),
    )


async def unhandled_handler(request: Request, exc: Exception) -> JSONResponse:
    trace_id = get_trace_id(request)
    return JSONResponse(
        status_code=500,
        content=error_envelope("SERVER", "Internal error", {}, trace_id),
    )


def register_exception_handlers(app: FastAPI) -> None:
    app.add_exception_handler(AppError, app_error_handler)
    app.add_exception_handler(StarletteHTTPException, http_exception_handler)
    app.add_exception_handler(RequestValidationError, request_validation_handler)
    app.add_exception_handler(Exception, unhandled_handler)
