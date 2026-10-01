"""Pure-stdlib RS256 fallback tests (firebase._HAS_CRYPTO forced off).

Uses the local `cryptography` lib ONLY to mint a throwaway keypair + cert —
the code under test (`rsa_verify`, the fallback branch) is stdlib-only,
which is what runs on Workers.
"""

import datetime as _dt
import sys
from pathlib import Path

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

import pytest  # noqa: E402

from app.adapters import firebase  # noqa: E402
from app.adapters.firebase import RealVerifier, UnauthError  # noqa: E402
from app.adapters.rsa_verify import (  # noqa: E402
    b64url_decode,
    rsa_pubkey_from_cert_pem,
    verify_rs256,
)

cryptography = pytest.importorskip("cryptography")
jwt = pytest.importorskip("jwt")

PROJECT = "test-proj"
KID = "k1"


def _keypair():
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import NameOID

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "t")])
    now = _dt.datetime.now(_dt.timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(name).issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - _dt.timedelta(days=1))
        .not_valid_after(now + _dt.timedelta(days=1))
        .sign(key, hashes.SHA256())
    )
    cert_pem = cert.public_bytes(serialization.Encoding.PEM).decode()
    key_pem = key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode()
    return key_pem, cert_pem


@pytest.fixture()
def pair():
    return _keypair()


def _token(key_pem, **claims):
    now = _dt.datetime.now(_dt.timezone.utc)
    base = {
        "sub": "uid-1",
        "phone_number": "+919876543210",
        "aud": PROJECT,
        "iss": f"https://securetoken.google.com/{PROJECT}",
        "iat": now,
        "exp": now + _dt.timedelta(minutes=30),
    }
    base.update(claims)
    return jwt.encode(base, key_pem, algorithm="RS256", headers={"kid": KID})


@pytest.fixture()
def verifier(pair, monkeypatch):
    _, cert_pem = pair
    monkeypatch.setattr(firebase, "_HAS_CRYPTO", False)
    monkeypatch.setattr(
        firebase, "_certs",
        {"keys": {KID: cert_pem}, "fetched": 9999999999.0},
    )
    return RealVerifier(project_id=PROJECT)


def test_fallback_valid(pair, verifier):
    key_pem, _ = pair
    out = verifier.verify_id_token(_token(key_pem))
    assert out == {"uid": "uid-1", "phone_number": "+919876543210"}


def test_fallback_tampered_payload(pair, verifier):
    key_pem, _ = pair
    h, p, s = _token(key_pem).split(".")
    bad = b64url_decode(p)
    bad = bad[:-1] + (b"0" if bad[-1:] != b"0" else b"1")
    import base64

    bad_p = base64.urlsafe_b64encode(bad).rstrip(b"=").decode()
    with pytest.raises(UnauthError):
        verifier.verify_id_token(f"{h}.{bad_p}.{s}")


def test_fallback_wrong_aud(pair, verifier):
    key_pem, _ = pair
    with pytest.raises(UnauthError):
        verifier.verify_id_token(_token(key_pem, aud="evil"))


def test_fallback_expired(pair, verifier):
    key_pem, _ = pair
    past = _dt.datetime.now(_dt.timezone.utc) - _dt.timedelta(hours=1)
    with pytest.raises(UnauthError):
        verifier.verify_id_token(_token(key_pem, exp=past, iat=past))


def test_fallback_garbage(verifier):
    with pytest.raises(UnauthError):
        verifier.verify_id_token("not.a.token")


def test_rsa_direct_roundtrip_and_flip(pair):
    key_pem, cert_pem = pair
    tok = _token(key_pem)
    h, p, s = tok.split(".")
    verify_rs256(f"{h}.{p}".encode("ascii"), b64url_decode(s), cert_pem)
    n, e = rsa_pubkey_from_cert_pem(cert_pem)
    assert e == 65537 and n.bit_length() == 2048
    bad = bytearray(b64url_decode(s))
    bad[10] ^= 0x01
    with pytest.raises(ValueError):
        verify_rs256(f"{h}.{p}".encode("ascii"), bytes(bad), cert_pem)
