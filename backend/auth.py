import asyncio

import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWKClient

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


def _decode_token(token: str) -> dict:
    jwks = _get_jwks_client()
    if jwks is not None:
        try:
            signing_key = jwks.get_signing_key_from_jwt(token)
            return jwt.decode(
                token,
                signing_key.key,
                algorithms=["ES256", "RS256"],
                audience="authenticated",
            )
        except jwt.InvalidTokenError:
            pass

    if not SUPABASE_JWT_SECRET:
        raise jwt.InvalidTokenError("JWT verification not configured")

    return jwt.decode(
        token,
        SUPABASE_JWT_SECRET,
        algorithms=["HS256"],
        audience="authenticated",
    )


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
            detail="Supabase JWT verification is not configured",
        )

    token = credentials.credentials
    try:
        payload = await asyncio.to_thread(_decode_token, token)
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired") from None
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token") from None

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="Token missing subject")
    return str(user_id)
