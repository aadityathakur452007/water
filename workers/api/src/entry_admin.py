"""Cloudflare Workers entrypoint — admin surface (`water-admin`).

Same fetch bridge and env pinning as ``entry.py``, minus the cron handler:
subscription/reminder jobs run only on ``water`` so they cannot double-run.
"""

import gc
from workers import WorkerEntrypoint

from app.core.worker_env import set_worker_env
from app.factory import create_app

app = create_app("admin")


class Default(WorkerEntrypoint):
    async def fetch(self, request):
        set_worker_env(self.env)
        from workers import asgi

        try:
            return await asgi.fetch(app, request.js_object, self.env)
        finally:
            gc.collect(1)
