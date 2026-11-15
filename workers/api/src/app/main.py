"""Local-dev / pytest shim. The factory lives in ``app.factory``.

``uvicorn app.main:app`` keeps working; Worker entry points import
``app.factory.create_app`` directly so they never build the "all" app first.
"""

from app.factory import create_app

app = create_app()
