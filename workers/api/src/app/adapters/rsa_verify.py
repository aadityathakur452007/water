"""Pure-stdlib RS256 verification (no C extensions).

Cloudflare Python Workers ban C extensions, so ``cryptography`` — PyJWT's
RS256 backend — cannot run in production. This module verifies the
RSA PKCS#1 v1.5 + SHA-256 signature of a Firebase ID token with only
``hashlib`` + ``pow()``, extracting the RSA public key from Google's X.509
PEM certificate via a minimal DER reader.

``firebase.py`` uses the ``cryptography`` path wherever it imports (local
dev) and falls back here otherwise — same checks, same errors.
"""

from __future__ import annotations

import base64
import hashlib
import hmac

# DigestInfo prefix for SHA-256 (RFC 8017 §9.2, note 1).
_SHA256_DER_PREFIX = bytes.fromhex("3031300d060960864801650304020105000420")


def b64url_decode(data: str) -> bytes:
    """Base64url-decode a JWT segment (adds the omitted padding)."""
    return base64.urlsafe_b64decode(data + "=" * (-len(data) % 4))


def _read_tlv(buf: bytes, pos: int) -> tuple[int, bytes, int]:
    """Read one DER tag-length-value at ``pos``; return (tag, value, next)."""
    tag = buf[pos]
    pos += 1
    length = buf[pos]
    pos += 1
    if length & 0x80:
        nbytes = length & 0x7F
        if nbytes == 0 or nbytes > 4:
            raise ValueError("bad DER length")
        length = int.from_bytes(buf[pos:pos + nbytes], "big")
        pos += nbytes
    end = pos + length
    if end > len(buf):
        raise ValueError("DER overrun")
    return tag, buf[pos:end], end


def _children(buf: bytes) -> list[tuple[int, bytes]]:
    """Split a constructed DER value into (tag, value) children, exactly."""
    out: list[tuple[int, bytes]] = []
    pos = 0
    while pos < len(buf):
        tag, val, pos = _read_tlv(buf, pos)
        out.append((tag, val))
    if pos != len(buf):
        raise ValueError("DER trailing bytes")
    return out


def rsa_pubkey_from_cert_pem(pem: str) -> tuple[int, int]:
    """Return ``(n, e)`` from the RSA SubjectPublicKeyInfo inside a PEM cert."""
    b64 = "".join(line.strip() for line in pem.splitlines() if "-----" not in line)
    der = base64.b64decode(b64)
    stack = [der]
    while stack:
        node = stack.pop()
        try:
            kids = _children(node)
        except ValueError:
            continue
        for tag, val in kids:
            if tag == 0x03 and len(val) > 2 and val[0] == 0x00:
                # BIT STRING, zero unused bits — candidate public key blob:
                # BIT STRING -> SEQUENCE { INTEGER n, INTEGER e }.
                try:
                    inner = _children(val[1:])
                    if len(inner) == 1 and inner[0][0] == 0x30:
                        inner = _children(inner[0][1])
                except ValueError:
                    continue
                if (
                    len(inner) == 2
                    and inner[0][0] == 0x02
                    and inner[1][0] == 0x02
                    and 128 <= len(inner[0][1]) <= 512
                ):
                    n = int.from_bytes(inner[0][1], "big")
                    e = int.from_bytes(inner[1][1], "big")
                    if n > 0 and e > 1:
                        return n, e
            if tag in (0x30, 0xA0):  # SEQUENCE / [0]-constructed (tbs version)
                stack.append(val)
    raise ValueError("no RSA public key in certificate")


def verify_rs256(signing_input: bytes, signature: bytes, cert_pem: str) -> None:
    """Verify an RS256 signature; raises ``ValueError`` when invalid.

    Args:
        signing_input: ``b"<base64url header>.<base64url payload>"``.
        signature: raw signature bytes (base64url-decoded ``sig`` segment).
        cert_pem: PEM X.509 certificate carrying the RSA public key.
    """
    n, e = rsa_pubkey_from_cert_pem(cert_pem)
    k = (n.bit_length() + 7) // 8
    if len(signature) != k:
        raise ValueError("bad signature length")
    s = int.from_bytes(signature, "big")
    if not 0 < s < n:
        raise ValueError("signature out of range")
    em = pow(s, e, n).to_bytes(k, "big")
    digest = hashlib.sha256(signing_input).digest()
    expected = (
        b"\x00\x01"
        + b"\xff" * (k - 3 - len(_SHA256_DER_PREFIX) - len(digest))
        + b"\x00"
        + _SHA256_DER_PREFIX
        + digest
    )
    if len(expected) != k or not hmac.compare_digest(em, expected):
        raise ValueError("bad signature")
