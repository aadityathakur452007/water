"""Workers env bridge (request-scoped).

On Cloudflare, vars/secrets live on the worker env object (``self.env``),
NOT in ``os.environ`` — which is why every ``os.environ.get`` in this
codebase silently returns ``None`` in production. ``set_worker_env`` is
called once per request by ``src/entry.py``; readers use :func:`env_get`,
which checks the request env first and falls back to ``os.environ``
(local dev, pytest — behavior there is byte-for-byte unchanged).
"""

from __future__ import annotations

import contextvars
import os

_current_env: contextvars.ContextVar[object | None] = contextvars.ContextVar(
    "shodasha_worker_env", default=None
)


def set_worker_env(env: object | None) -> None:
    """Pin the current request's worker env (called by the entrypoint)."""
    _current_env.set(env)


def current_env() -> object | None:
    """Return the pinned request env, or None outside a worker request."""
    return _current_env.get()


def env_get(name: str, default: str | None = None) -> str | None:
    """Read ``name`` from the request worker env, else ``os.environ``."""
    env = _current_env.get()
    if env is not None:
        try:
            value = getattr(env, name, None)
            if value is None and hasattr(env, name.upper()):
                value = getattr(env, name.upper(), None)
            if value is None and hasattr(env, name.lower()):
                value = getattr(env, name.lower(), None)
            if value is None and hasattr(env, "get"):
                value = env.get(name) or env.get(name.upper()) or env.get(name.lower())
        except Exception:
            value = None
        if value is not None:
            return str(value)
    return os.environ.get(name) or os.environ.get(name.upper()) or os.environ.get(name.lower()) or default

