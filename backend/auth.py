import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from config import SUPABASE_JWT_SECRET

_bearer = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> str:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=401,
            detail="Missing or invalid Authorization header",
        )
    if not SUPABASE_JWT_SECRET:
        raise HTTPException(
            status_code=500,
            detail="SUPABASE_JWT_SECRET is not configured",
        )

    token = credentials.credentials
    try:
        payload = jwt.decode(
            token,
            SUPABASE_JWT_SECRET,
            algorithms=["HS256"],
            audience="authenticated",
        )
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired") from None
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token") from None

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="Token missing subject")
    return str(user_id)
