"""Cancellazione account ed export dei dati conservati sul server."""

from __future__ import annotations

import json
import logging
import tempfile
import uuid
import zipfile
from pathlib import Path

import httpx
from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from config import AUTH_ADMIN_URL, SERVICE_ROLE_KEY
from models.deleted_note import DeletedNoteDB
from models.job import JobDB
from models.note import NoteDB
from models.note_share import NoteShareDB
from models.server_usage import UserServerUsage
from models.upload_session import UploadSessionDB
from services.upload_session_service import _delete_session_files

logger = logging.getLogger(__name__)

STORAGE_DIR = Path(__file__).resolve().parent.parent / "storage"


def _storage_filename(raw: str | None) -> str | None:
    if not raw or not raw.strip():
        return None
    name = Path(raw).name
    if not name or name in {".", ".."}:
        return None
    root = STORAGE_DIR.resolve()
    candidate = (STORAGE_DIR / name).resolve()
    if candidate.parent != root:
        return None
    return name


def ensure_can_delete_account(user_id: str) -> None:
    try:
        uuid.UUID(user_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid user id") from exc
    if not SERVICE_ROLE_KEY:
        raise HTTPException(
            status_code=503,
            detail="Cancellazione account non configurata sul server",
        )


def purge_user_data(db: Session, user_id: str) -> None:
    """Rimuove note, audio, condivisioni, upload, job e quota dell'utente."""
    notes = list(db.scalars(select(NoteDB).where(NoteDB.user_id == user_id)).all())
    shares = list(
        db.scalars(
            select(NoteShareDB).where(NoteShareDB.owner_user_id == user_id)
        ).all()
    )
    sessions = list(
        db.scalars(
            select(UploadSessionDB).where(UploadSessionDB.user_id == user_id)
        ).all()
    )
    jobs = list(db.scalars(select(JobDB).where(JobDB.user_id == user_id)).all())
    tombstones = list(
        db.scalars(
            select(DeletedNoteDB).where(DeletedNoteDB.user_id == user_id)
        ).all()
    )
    usage = db.get(UserServerUsage, user_id)

    filenames: set[str] = set()
    session_ids: list[str] = []
    for note in notes:
        name = _storage_filename(note.audio_filename)
        if name:
            filenames.add(name)
    for session in sessions:
        session_ids.append(session.id)
        name = _storage_filename(session.assembled_path)
        if name:
            filenames.add(name)

    for share in shares:
        db.delete(share)
    for note in notes:
        db.delete(note)
    for session in sessions:
        db.delete(session)
    for job in jobs:
        db.delete(job)
    for tombstone in tombstones:
        db.delete(tombstone)
    if usage is not None:
        db.delete(usage)
    db.commit()

    for name in filenames:
        try:
            still_used = db.scalar(
                select(NoteDB.id).where(NoteDB.audio_filename == name)
            )
            if still_used is not None:
                continue
            path = STORAGE_DIR / name
            if path.is_file():
                path.unlink(missing_ok=True)
        except OSError:
            logger.warning("Audio non rimosso: %s", name)

    for upload_id in session_ids:
        if "/" in upload_id or "\\" in upload_id:
            continue
        _delete_session_files(upload_id)


def build_export_zip(db: Session, user_id: str) -> Path:
    notes = list(
        db.scalars(
            select(NoteDB)
            .where(NoteDB.user_id == user_id)
            .order_by(NoteDB.created_at.asc())
        ).all()
    )
    payload: list[dict] = []
    audio_files: list[tuple[Path, str]] = []
    for note in notes:
        entry = {
            "note_id": note.id,
            "title": note.title,
            "summary": note.summary,
            "formatted_transcription": note.formatted_transcription,
            "raw_transcription": note.raw_transcription,
            "highlights": note.highlights,
            "key_data": note.key_data,
            "speaker_view": note.speaker_view,
            "mind_map": note.mind_map or [],
            "transcript_segments": note.transcript_segments or [],
            "audio_duration": note.audio_duration,
            "source_language": note.source_language,
            "output_language": note.output_language,
            "created_at": note.created_at.isoformat(),
            "audio_file": None,
        }
        name = _storage_filename(note.audio_filename)
        path = STORAGE_DIR / name if name else None
        if path is not None and path.is_file():
            arcname = f"audio/{note.id}{path.suffix.lower() or '.m4a'}"
            entry["audio_file"] = arcname
            audio_files.append((path, arcname))
        payload.append(entry)

    handle = tempfile.NamedTemporaryFile(delete=False, suffix=".zip")
    handle.close()
    zip_path = Path(handle.name)
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(
            "notes.json",
            json.dumps(payload, ensure_ascii=False, indent=2),
        )
        for path, arcname in audio_files:
            archive.write(path, arcname=arcname)
    return zip_path


async def delete_auth_user(user_id: str) -> None:
    try:
        uuid.UUID(user_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid user id") from exc
    if not SERVICE_ROLE_KEY:
        raise HTTPException(
            status_code=503,
            detail="Cancellazione account non configurata sul server",
        )

    url = f"{AUTH_ADMIN_URL}/admin/users/{user_id}"
    headers = {
        "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
        "apikey": SERVICE_ROLE_KEY,
    }
    try:
        async with httpx.AsyncClient(timeout=20) as client:
            response = await client.delete(url, headers=headers)
    except httpx.HTTPError as exc:
        logger.warning("GoTrue delete failed for %s: %s", user_id, exc)
        raise HTTPException(
            status_code=502,
            detail="Dati cancellati, ma l'accesso non si è chiuso. Riprova.",
        ) from exc

    if response.status_code in {200, 204, 404}:
        return
    logger.warning(
        "GoTrue delete status %s for %s",
        response.status_code,
        user_id,
    )
    raise HTTPException(
        status_code=502,
        detail="Dati cancellati, ma l'accesso non si è chiuso. Riprova.",
    )


def remove_export_file(path: str) -> None:
    Path(path).unlink(missing_ok=True)
