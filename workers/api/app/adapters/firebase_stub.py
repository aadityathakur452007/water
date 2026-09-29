"""Slice-1 Firebase auth adapter stub.

Interface is shaped like the future real adapter so slice-2 swaps this
one file: same class name, same method name, same return contract.
"""

from __future__ import annotations

import os
import uuid


class StubError(RuntimeError):
    """Raised whenever the slice-1 stub stands in for the real verifier."""


class FirebaseStub:
    """Stand-in for Firebase ID-token verification (slice-2: real verifier)."""

    def verify_id_token(self, token: str) -> dict:
        """Verify a Firebase ID token.

        Future real-adapter contract: returns ``{"uid": ..., "phone_number": ...}``
        for a valid token; raises on invalid/expired tokens.

        Slice-1: always raises :class:`StubError` — there is no verifier yet.
        """
        tid = uuid.uuid4().hex[:8]
        if not token:
            raise StubError(f"missing id token (trace_id={tid}) — slice-2 wires Firebase")
        project = os.environ.get("FIREBASE_PROJECT_ID")
        hint = (
            f"FIREBASE_PROJECT_ID={project} is set but the verifier is not swapped yet"
            if project
            else "set FIREBASE_PROJECT_ID and swap adapters/firebase_stub.py for the real verifier"
        )
        raise StubError(f"firebase not configured — slice-2 (trace_id={tid}): {hint}")
