"""Cloudflare Workers entrypoint — production only.

Local dev and pytest keep using ``app.main:create_app()`` on uvicorn +
sqlite, untouched. Shape mirrors the official FastAPI + cron examples
(cloudflare/python-workers-examples): a ``Default`` entrypoint whose
``fetch`` bridges into FastAPI via the Workers ASGI server, with the
worker env (D1 binding, vars, secrets) passed through so request handlers
can reach it at ``request.scope["env"]``.
"""

import gc
from workers import WorkerEntrypoint

from app.core.worker_env import set_worker_env
from app.main import create_app

app = create_app()


class Default(WorkerEntrypoint):
    async def fetch(self, request):
        # Pin the request env (vars/secrets/bindings) for this request —
        # readers via app.core.worker_env.env_get. os.environ is empty on
        # Workers, so without this every env lookup returns None in prod.
        set_worker_env(self.env)
        from workers import asgi

        try:
            return await asgi.fetch(app, request.js_object, self.env)
        finally:
            # Memory flushing: Pyodide creates JsProxy objects for incoming requests and
            # D1 query results. Explicit generational collection ensures circular references
            # between Python and V8 heap are freed, preventing the 128 MB isolate heap limit
            # from being exhausted under sustained traffic.
            gc.collect(1)

    async def scheduled(self, controller, env, ctx):
        set_worker_env(env)
        # Phase-B done: jobs (app/jobs/scheduler.py) are async over the Conn
        # facade and could run on D1Conn(env.DB) here. This tick stays a
        # logged no-op until the cron wiring is tested against real D1.
        print("water: cron tick received, scheduler async-ready, wiring pending.")
