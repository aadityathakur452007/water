"""Cloudflare Workers entrypoint — production only.

Local dev and pytest keep using ``app.main:create_app()`` on uvicorn +
sqlite, untouched. Shape mirrors the official FastAPI + cron examples
(cloudflare/python-workers-examples): a ``Default`` entrypoint whose
``fetch`` bridges into FastAPI via the Workers ASGI server, with the
worker env (D1 binding, vars, secrets) passed through so request handlers
can reach it at ``request.scope["env"]``.
"""

from workers import WorkerEntrypoint

from app.main import create_app

app = create_app()


class Default(WorkerEntrypoint):
    async def fetch(self, request):
        from workers import asgi

        return await asgi.fetch(app, request.js_object, self.env)

    async def scheduled(self, controller, env, ctx):
        # T2: repositories are sync-sqlite today and D1 is async-only, so
        # jobs (app/jobs/scheduler.py) cannot run on D1 yet. This tick
        # stays a logged no-op until the async-D1 conversion lands.
        print("water: cron tick received, scheduler pending async-D1 conversion (T2).")
