"""Pytest bootstrap: expose src/ (the app package) on sys.path.

Layout is src-first for Cloudflare (entry.py lives beside the app package).
Local runs use the same rule: prefix commands with PYTHONPATH=src, e.g.
PYTHONPATH=src python -m uvicorn app.main:app / PYTHONPATH=src python -m app.migrate
"""

import sys
from pathlib import Path

SRC = Path(__file__).resolve().parent / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))
