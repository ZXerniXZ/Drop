import secrets
import shutil
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from models.note import NoteDB
from models.note_share import NoteShareDB

STORAGE_DIR = Path(__file__).resolve().parent.parent / "storage"


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _copy_audio_file(filename: str) -> str:
    if not filename:
        return ""
    source = STORAGE_DIR / Path(filename).name
    if not source.is_file():
        return ""
    dest_name = f"{uuid.uuid4()}{source.suffix}"
    STORAGE_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, STORAGE_DIR / dest_name)
    return dest_name


def _note_is_shareable(note: NoteDB) -> bool:
    return bool(
        (note.raw_transcription or "").strip()
        or (note.formatted_transcription or "").strip()
        or (note.summary or "").strip()
    )


def get_active_share(db: Session, note_id: str, user_id: str) -> NoteShareDB | None:
    stmt = (
        select(NoteShareDB)
        .where(
            NoteShareDB.note_id == note_id,
            NoteShareDB.owner_user_id == user_id,
            NoteShareDB.revoked_at.is_(None),
        )
        .order_by(NoteShareDB.created_at.desc())
    )
    return db.scalars(stmt).first()


def create_or_reuse_share(db: Session, note: NoteDB, user_id: str) -> NoteShareDB:
    if note.user_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    if not _note_is_shareable(note):
        raise HTTPException(
            status_code=409,
            detail="La nota non e' ancora pronta da condividere",
        )
    existing = get_active_share(db, note.id, user_id)
    if existing is not None:
        return existing
    share = NoteShareDB(
        token=secrets.token_urlsafe(24),
        note_id=note.id,
        owner_user_id=user_id,
        created_at=_utc_now(),
    )
    db.add(share)
    db.commit()
    db.refresh(share)
    return share


def revoke_share(db: Session, note: NoteDB, user_id: str) -> bool:
    if note.user_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    share = get_active_share(db, note.id, user_id)
    if share is None:
        return False
    share.revoked_at = _utc_now()
    db.add(share)
    db.commit()
    return True


def _copy_note_fields(source: NoteDB, *, new_id: str, user_id: str, token: str) -> NoteDB:
    return NoteDB(
        id=new_id,
        user_id=user_id,
        title=source.title,
        summary=source.summary,
        formatted_transcription=source.formatted_transcription,
        raw_transcription=source.raw_transcription,
        highlights=list(source.highlights or []),
        key_data=dict(source.key_data or {}),
        speaker_view=list(source.speaker_view or []),
        transcript_segments=list(source.transcript_segments or []),
        audio_duration=source.audio_duration,
        audio_filename=_copy_audio_file(source.audio_filename),
        source_language=source.source_language,
        output_language=source.output_language,
        source_share_token=token,
        created_at=_utc_now(),
    )


def claim_share(db: Session, token: str, user_id: str) -> tuple[NoteDB, bool]:
    """Copia la nota condivisa nell'account. Ritorna (nota, already_owned_or_claimed)."""
    share = db.get(NoteShareDB, token)
    if share is None or share.revoked_at is not None:
        raise HTTPException(status_code=404, detail="Link non valido o scaduto")

    source = db.get(NoteDB, share.note_id)
    if source is None:
        raise HTTPException(status_code=404, detail="Nota non disponibile")

    if source.user_id == user_id:
        return source, True

    existing_stmt = select(NoteDB).where(
        NoteDB.user_id == user_id,
        NoteDB.source_share_token == token,
    )
    existing = db.scalars(existing_stmt).first()
    if existing is not None:
        return existing, True

    copied = _copy_note_fields(
        source,
        new_id=str(uuid.uuid4()),
        user_id=user_id,
        token=token,
    )
    db.add(copied)
    db.commit()
    db.refresh(copied)
    return copied, False


def upsert_published_note(
    db: Session,
    *,
    user_id: str,
    note_id: str,
    payload: dict[str, Any],
    audio_filename: str,
) -> NoteDB:
    existing = db.get(NoteDB, note_id)
    if existing is not None and existing.user_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden")

    title = str(payload.get("title") or "").strip() or "Voice note"
    if existing is None:
        note = NoteDB(
            id=note_id,
            user_id=user_id,
            title=title[:80],
        )
    else:
        note = existing
        note.title = title[:80]

    note.summary = str(payload.get("summary") or "")
    note.formatted_transcription = str(
        payload.get("formatted_transcription") or payload.get("transcription") or ""
    )
    note.raw_transcription = str(payload.get("raw_transcription") or "")
    highlights = payload.get("highlights") or []
    note.highlights = highlights if isinstance(highlights, list) else []
    key_data = payload.get("key_data") or {}
    note.key_data = key_data if isinstance(key_data, dict) else {}
    speaker_view = payload.get("speaker_view") or []
    note.speaker_view = speaker_view if isinstance(speaker_view, list) else []
    segments = payload.get("transcript_segments") or []
    note.transcript_segments = segments if isinstance(segments, list) else []
    duration = payload.get("audio_duration")
    note.audio_duration = float(duration) if duration is not None else note.audio_duration
    if audio_filename:
        note.audio_filename = audio_filename
    if payload.get("source_language"):
        note.source_language = str(payload["source_language"])
    if payload.get("output_language"):
        note.output_language = str(payload["output_language"])

    db.add(note)
    db.commit()
    db.refresh(note)
    return note
