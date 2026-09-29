"""Adapter package — external-service boundary (swappable per slice)."""

from app.adapters.firebase_stub import FirebaseStub, StubError

__all__ = ["FirebaseStub", "StubError"]
