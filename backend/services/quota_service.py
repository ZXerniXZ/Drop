from datetime import datetime, timezone

from fastapi import HTTPException
from sqlalchemy import func, select, text
from sqlalchemy.exc import IntegrityError

from config import SERVER_AUDIO_QUOTA_SECONDS
from database import SessionLocal
from models.note import NoteDB
from models.server_usage import UserServerUsage

QUOTA_CODE = "server_quota_exceeded"
QUOTA_MESSAGE = (
    "Hai esaurito le 2 ore di trascrizione incluse. "
    "Aggiungi una chiave OpenRouter in Account."
)


class QuotaExceeded(Exception):
    def __init__(self, used_seconds: float, limit_seconds: float):
        self.used_seconds = used_seconds
        self.limit_seconds = limit_seconds
        super().__init__(QUOTA_MESSAGE)


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def quota_limit_seconds() -> float:
    return max(0.0, float(SERVER_AUDIO_QUOTA_SECONDS))


def usage_snapshot(user_id: str) -> dict[str, float | int]:
    limit = quota_limit_seconds()
    used = _billed_seconds(user_id)
    remaining = max(0.0, limit - used)
    return {
        "limit_seconds": int(round(limit)),
        "used_seconds": int(round(used)),
        "remaining_seconds": int(round(remaining)),
    }


def quota_http_exception(user_id: str) -> HTTPException:
    snap = usage_snapshot(user_id)
    return HTTPException(
        status_code=402,
        detail={
            "code": QUOTA_CODE,
            "message": QUOTA_MESSAGE,
            **snap,
        },
    )


def raise_if_cannot_accept(user_id: str, incoming_seconds: float | None) -> None:
    """Blocco preventivo prima di accettare un job sul server."""
    snap = usage_snapshot(user_id)
    if snap["remaining_seconds"] <= 0:
        raise quota_http_exception(user_id)
    if incoming_seconds is None:
        return
    incoming = max(0.0, float(incoming_seconds))
    if incoming <= 0:
        return
    if snap["used_seconds"] + incoming > snap["limit_seconds"] + 1:
        raise quota_http_exception(user_id)


def consume(user_id: str, seconds: float) -> None:
    """Addebita i secondi in modo atomico. Solleva QuotaExceeded se sfora."""
    amount = max(0.0, float(seconds))
    if amount <= 0:
        return
    limit = quota_limit_seconds()
    db = SessionLocal()
    try:
        _ensure_row(db, user_id)
        result = db.execute(
            text(
                "UPDATE user_server_usage "
                "SET billed_seconds = billed_seconds + :amount, "
                "updated_at = :now "
                "WHERE user_id = :user_id "
                "AND billed_seconds + :amount <= :limit + 1"
            ),
            {
                "amount": amount,
                "now": _utc_now().isoformat(),
                "user_id": user_id,
                "limit": limit,
            },
        )
        db.commit()
        if result.rowcount == 0:
            used = _billed_seconds(user_id)
            raise QuotaExceeded(used, limit)
    except QuotaExceeded:
        db.rollback()
        raise
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def refund(user_id: str, seconds: float) -> None:
    amount = max(0.0, float(seconds))
    if amount <= 0:
        return
    db = SessionLocal()
    try:
        _ensure_row(db, user_id)
        db.execute(
            text(
                "UPDATE user_server_usage "
                "SET billed_seconds = MAX(billed_seconds - :amount, 0), "
                "updated_at = :now "
                "WHERE user_id = :user_id"
            ),
            {"amount": amount, "now": _utc_now().isoformat(), "user_id": user_id},
        )
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def _billed_seconds(user_id: str) -> float:
    db = SessionLocal()
    try:
        row = _ensure_row(db, user_id)
        return float(row.billed_seconds or 0.0)
    finally:
        db.close()


def _ensure_row(db, user_id: str) -> UserServerUsage:
    row = db.get(UserServerUsage, user_id)
    if row is not None:
        return row
    total = db.scalar(
        select(func.coalesce(func.sum(NoteDB.audio_duration), 0.0)).where(
            NoteDB.user_id == user_id
        )
    )
    row = UserServerUsage(
        user_id=user_id,
        billed_seconds=float(total or 0.0),
        updated_at=_utc_now(),
    )
    db.add(row)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        existing = db.get(UserServerUsage, user_id)
        if existing is None:
            raise
        return existing
    db.refresh(row)
    return row
