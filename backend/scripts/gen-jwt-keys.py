#!/usr/bin/env python3
"""Genera JWT_SECRET, ANON_KEY e SERVICE_ROLE_KEY per GoTrue self-host.

Uso sulla Raspberry:
  python3 scripts/gen-jwt-keys.py >> .env

Oppure copia a mano i valori stampati in backend/.env.
Le chiavi non vanno committate.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
import time

# Come gli esempi ufficiali supabase/docker: validita' ~10 anni per anon/service.
_TTL_SECONDS = 10 * 365 * 24 * 3600


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _hs256_jwt(payload: dict, secret: str) -> str:
    header = _b64url(
        json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode()
    )
    body = _b64url(json.dumps(payload, separators=(",", ":")).encode())
    signing_input = f"{header}.{body}".encode("ascii")
    signature = hmac.new(secret.encode("utf-8"), signing_input, hashlib.sha256).digest()
    return f"{header}.{body}.{_b64url(signature)}"


def main() -> None:
    secret = secrets.token_urlsafe(40)
    now = int(time.time())
    exp = now + _TTL_SECONDS
    claims = {"iss": "supabase", "iat": now, "exp": exp}
    anon = _hs256_jwt({**claims, "role": "anon"}, secret)
    service = _hs256_jwt({**claims, "role": "service_role"}, secret)
    postgres_password = secrets.token_urlsafe(24)

    print("# Generato da scripts/gen-jwt-keys.py — non committare")
    print(f"AUTH_POSTGRES_PASSWORD={postgres_password}")
    print(f"JWT_SECRET={secret}")
    print(f"SUPABASE_JWT_SECRET={secret}")
    print(f"ANON_KEY={anon}")
    print(f"SERVICE_ROLE_KEY={service}")


if __name__ == "__main__":
    main()
