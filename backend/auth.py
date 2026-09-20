import asyncio

import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWKClient
from jwt.exceptions import PyJWKClientError

from config import SUPABASE_JWT_SECRET, SUPABASE_URL

_bearer = HTTPBearer(auto_error=False)

_jwks_client: PyJWKClient | None = None


def _get_jwks_client() -> PyJWKClient | None:
    global _jwks_client
    if not SUPABASE_URL:
        return None
    if _jwks_client is None:
        _jwks_client = PyJWKClient(f"{SUPABASE_URL}/auth/v1/.well-known/jwks.json")
    return _jwks_client


class JwksUnavailableError(Exception):
    """Le chiavi pubbliche Auth non sono raggiungibili."""


def _decode_hs256(token: str) -> dict:
    return jwt.decode(
        token,
        SUPABASE_JWT_SECRET,
        algorithms=["HS256"],
        audience="authenticated",
    )


def _decode_jwks(token: str) -> dict:
    jwks = _get_jwks_client()
    if jwks is None:
        raise jwt.InvalidTokenError("JWT verification not configured")
    signing_key = jwks.get_signing_key_from_jwt(token)
    return jwt.decode(
        token,
        signing_key.key,
        algorithms=["ES256", "RS256"],
        audience="authenticated",
    )


def _decode_token(token: str) -> dict:
    # GoTrue self-host firma HS256 con JWT_SECRET (stesso valore di
    # SUPABASE_JWT_SECRET). JWKS resta solo come fallback per token Cloud.
    hs256_error: jwt.InvalidTokenError | None = None
    if SUPABASE_JWT_SECRET:
        try:
            return _decode_hs256(token)
        except jwt.ExpiredSignatureError:
            raise
        except jwt.InvalidTokenError as exc:
            hs256_error = exc
            if not SUPABASE_URL:
                raise

    try:
        return _decode_jwks(token)
    except PyJWKClientError as exc:
        if hs256_error is not None:
            raise hs256_error from exc
        raise JwksUnavailableError(
            "Cannot reach Auth public keys and no JWT secret is configured"
        ) from exc


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> str:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=401,
            detail="Missing or invalid Authorization header",
        )
    if not SUPABASE_JWT_SECRET and not SUPABASE_URL:
        raise HTTPException(
            status_code=500,
            detail="Auth JWT verification is not configured",
        )

    token = credentials.credentials
    try:
        payload = await asyncio.to_thread(_decode_token, token)
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired") from None
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token") from None
    except JwksUnavailableError:
        raise HTTPException(
            status_code=503,
            detail="Authentication temporarily unavailable, retry shortly",
        ) from None

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="Token missing subject")
    return str(user_id)
