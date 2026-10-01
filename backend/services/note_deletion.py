"""Cancellazione di una nota e blocco contro la ricreazione da job in corso."""

from __future__ import annotations

import logging
import re
from pathlib import Path

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from models.deleted_note import DeletedNoteDB
from models.note import NoteDB
from models.note_share import NoteShareDB

logger = logging.getLogger(__name__)

STORAGE_DIR = Path(__file__).resolve().parent.parent / "storage"
_NOTE_ID = re.compile(r"^[A-Za-z0-9_-]{1,80}$")


class NoteWasDeleted(Exception):
    """Il job ha finito dopo che l'utente aveva gia' cancellato la nota."""


def _require_note_id(note_id: str) -> str:
    cleaned = (note_id or "").strip()
    if _NOTE_ID.fullmatch(cleaned) is None:
        raise HTTPException(status_code=400, detail="Invalid note id")
    return cleaned


def _storage_filename(raw: str | None) -> str | None:
    if not raw or not raw.strip():
        return None
    name = Path(raw).name
    if not name or name in {".", ".."}:
        return None
    candidate = (STORAGE_DIR / name).resolve()
    if candidate.parent != STORAGE_DIR.resolve():
        return None
    return name


def note_was_deleted(db: Session, note_id: str, user_id: str) -> bool:
    cleaned = (note_id or "").strip()
    if not cleaned:
        return False
    tombstone = db.get(DeletedNoteDB, cleaned)
    return tombstone is not None and tombstone.user_id == user_id


def delete_note_for_user(db: Session, note_id: str, user_id: str) -> None:
    """Segna l'id come cancellato e rimuove nota, condivisioni e audio.

    La riga in deleted_notes viene scritta anche se la nota non e' ancora
    sul server: un'analisi partita prima della cancellazione non puo' ricrearla.
    """
    cleaned = _require_note_id(note_id)
    note = db.get(NoteDB, cleaned)
    if note is not None and note.user_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden")

    tombstone = db.get(DeletedNoteDB, cleaned)
    if tombstone is not None and tombstone.user_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    if tombstone is None:
        db.add(DeletedNoteDB(id=cleaned, user_id=user_id))

    audio_name = _storage_filename(note.audio_filename) if note is not None else None
    if note is not None:
        shares = db.scalars(
            select(NoteShareDB).where(NoteShareDB.note_id == cleaned)
        ).all()
        for share in shares:
            db.delete(share)
        db.delete(note)

    db.commit()
    _unlink_audio_if_unused(db, audio_name)


def _unlink_audio_if_unused(db: Session, name: str | None) -> None:
    if not name:
        return
    try:
        still_used = db.scalar(select(NoteDB.id).where(NoteDB.audio_filename == name))
        if still_used is not None:
            return
        path = STORAGE_DIR / name
        if path.is_file():
            path.unlink(missing_ok=True)
    except OSError:
        logger.warning("Audio non rimosso: %s", name)
