import hashlib
import shutil
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from database import SessionLocal
from models.upload_session import (
    CHUNK_SIZE,
    MAX_UPLOAD_BYTES,
    SESSION_TTL_HOURS,
    UploadSessionDB,
    _chunk_byte_size,
    expected_total_chunks,
)

STORAGE_DIR = Path(__file__).resolve().parent.parent / "storage"
UPLOADS_DIR = STORAGE_DIR / "uploads"


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _session_chunks_dir(upload_id: str) -> Path:
    return UPLOADS_DIR / upload_id


def _chunk_path(upload_id: str, index: int) -> Path:
    return _session_chunks_dir(upload_id) / f"{index}.part"


def cleanup_expired_sessions() -> None:
    db = SessionLocal()
    try:
        now = _utc_now()
        expired = db.scalars(
            select(UploadSessionDB).where(UploadSessionDB.expires_at < now)
        ).all()
        for session in expired:
            _delete_session_files(session.id)
            db.delete(session)
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def _get_owned_session(
    db: Session, upload_id: str, user_id: str
) -> UploadSessionDB:
    session = db.get(UploadSessionDB, upload_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Upload session not found")
    if session.user_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    if session.expires_at < _utc_now():
        raise HTTPException(status_code=410, detail="Upload session expired")
    return session


def _delete_session_files(upload_id: str) -> None:
    chunks_dir = _session_chunks_dir(upload_id)
    if chunks_dir.exists():
        shutil.rmtree(chunks_dir, ignore_errors=True)


def create_session(
    *,
    user_id: str,
    filename: str,
    total_size: int,
    total_chunks: int,
    metadata: dict[str, Any],
) -> UploadSessionDB:
    if total_size <= 0 or total_size > MAX_UPLOAD_BYTES:
        raise HTTPException(
            status_code=400,
            detail=f"total_size must be between 1 and {MAX_UPLOAD_BYTES}",
        )

    expected = expected_total_chunks(total_size)
    if total_chunks != expected:
        raise HTTPException(
            status_code=400,
            detail=f"total_chunks must be {expected} for total_size {total_size}",
        )

    upload_id = str(uuid.uuid4())
    now = _utc_now()
    session = UploadSessionDB(
        id=upload_id,
        user_id=user_id,
        filename=Path(filename or "audio.m4a").name,
        total_size=total_size,
        total_chunks=total_chunks,
        received_chunks=[],
        metadata_json=metadata,
        status="uploading",
        created_at=now,
        expires_at=now + timedelta(hours=SESSION_TTL_HOURS),
    )

    _session_chunks_dir(upload_id).mkdir(parents=True, exist_ok=True)

    db = SessionLocal()
    try:
        db.add(session)
        db.commit()
        db.refresh(session)
        return session
    except Exception:
        db.rollback()
        _delete_session_files(upload_id)
        raise
    finally:
        db.close()


def get_session_status(upload_id: str, *, user_id: str) -> dict[str, Any]:
    db = SessionLocal()
    try:
        session = _get_owned_session(db, upload_id, user_id)
        return session.to_status_dict()
    finally:
        db.close()


def save_chunk(
    upload_id: str,
    *,
    user_id: str,
    index: int,
    data: bytes,
) -> dict[str, Any]:
    db = SessionLocal()
    try:
        session = _get_owned_session(db, upload_id, user_id)
        if session.status != "uploading":
            raise HTTPException(
                status_code=409, detail="Upload session is not accepting chunks"
            )
        if index < 0 or index >= session.total_chunks:
            raise HTTPException(status_code=400, detail="Invalid chunk index")

        expected_size = _chunk_byte_size(
            session.total_size, session.total_chunks, index
        )
        if len(data) != expected_size:
            raise HTTPException(
                status_code=400,
                detail=f"Chunk {index} must be exactly {expected_size} bytes",
            )

        chunk_file = _chunk_path(upload_id, index)
        chunk_file.write_bytes(data)

        received = set(session.received_chunks or [])
        received.add(index)
        session.received_chunks = sorted(received)
        db.add(session)
        db.commit()
        db.refresh(session)
        return session.to_status_dict()
    except HTTPException:
        db.rollback()
        raise
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def _assemble_file(session: UploadSessionDB) -> Path:
    STORAGE_DIR.mkdir(parents=True, exist_ok=True)
    suffix = Path(session.filename).suffix or ".m4a"
    saved_name = f"{uuid.uuid4()}{suffix}"
    destination = STORAGE_DIR / saved_name

    with destination.open("wb") as out:
        for index in range(session.total_chunks):
            chunk_file = _chunk_path(session.id, index)
            if not chunk_file.exists():
                raise HTTPException(
                    status_code=400, detail=f"Missing chunk {index}"
                )
            with chunk_file.open("rb") as src:
                shutil.copyfileobj(src, out, length=CHUNK_SIZE)

    if destination.stat().st_size != session.total_size:
        destination.unlink(missing_ok=True)
        raise HTTPException(
            status_code=400,
            detail="Assembled file size does not match total_size",
        )

    return destination


def complete_session(upload_id: str, *, user_id: str) -> tuple[str, str, dict[str, Any]]:
    db = SessionLocal()
    try:
        session = _get_owned_session(db, upload_id, user_id)
        if session.status == "completed" and session.assembled_path:
            path = Path(session.assembled_path)
            saved_name = path.name
            return saved_name, str(path), session.metadata_json

        if session.status != "uploading":
            raise HTTPException(status_code=409, detail="Upload session not active")

        received = set(session.received_chunks or [])
        expected = set(range(session.total_chunks))
        if received != expected:
            missing = sorted(expected - received)
            raise HTTPException(
                status_code=400,
                detail=f"Missing chunks: {missing}",
            )

        destination = _assemble_file(session)
        session.status = "completed"
        session.assembled_path = str(destination)
        db.add(session)
        db.commit()

        _delete_session_files(upload_id)
        return destination.name, str(destination), session.metadata_json
    except HTTPException:
        db.rollback()
        raise
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def delete_session(upload_id: str, *, user_id: str) -> None:
    db = SessionLocal()
    try:
        session = _get_owned_session(db, upload_id, user_id)
        _delete_session_files(upload_id)
        db.delete(session)
        db.commit()
    except HTTPException:
        db.rollback()
        raise
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def compute_file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(CHUNK_SIZE):
            digest.update(chunk)
    return digest.hexdigest()
