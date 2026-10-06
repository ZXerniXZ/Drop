"""Cartelle delle note, una libreria per account."""

from __future__ import annotations

import re
from datetime import datetime, timezone

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from models.note import NoteDB
from models.note_folder import NoteFolderDB

_FOLDER_ID = re.compile(r"^[A-Za-z0-9_-]{1,80}$")


def collect_subtree_ids(parent_by_id: dict[str, str | None], root_id: str) -> set[str]:
    children: dict[str, list[str]] = {}
    for folder_id, parent_id in parent_by_id.items():
        if parent_id:
            children.setdefault(parent_id, []).append(folder_id)

    ids: set[str] = set()

    def walk(folder_id: str) -> None:
        if folder_id in ids:
            return
        ids.add(folder_id)
        for child_id in children.get(folder_id, []):
            walk(child_id)

    walk(root_id)
    return ids


def _require_folder_id(folder_id: str) -> str:
    cleaned = (folder_id or "").strip()
    if _FOLDER_ID.fullmatch(cleaned) is None:
        raise HTTPException(status_code=400, detail="Invalid folder id")
    return cleaned


def _parse_created_at(raw: str | None) -> datetime:
    if not raw or not raw.strip():
        return datetime.now(timezone.utc)
    try:
        parsed = datetime.fromisoformat(raw.strip().replace("Z", "+00:00"))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid created_at") from exc
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed


def _owned_folders(db: Session, user_id: str) -> list[NoteFolderDB]:
    stmt = (
        select(NoteFolderDB)
        .where(NoteFolderDB.user_id == user_id)
        .order_by(NoteFolderDB.created_at.asc())
    )
    return list(db.scalars(stmt).all())


def _parent_creates_cycle(
    parent_by_id: dict[str, str | None],
    folder_id: str,
    parent_id: str | None,
) -> bool:
    seen: set[str] = set()
    current = parent_id
    while current:
        if current == folder_id or current in seen:
            return True
        seen.add(current)
        current = parent_by_id.get(current)
    return False


def list_folders(db: Session, user_id: str) -> list[dict[str, str | None]]:
    return [folder.to_dict() for folder in _owned_folders(db, user_id)]


def upsert_folder(
    db: Session,
    user_id: str,
    folder_id: str,
    name: str,
    parent_id: str | None,
    created_at: str | None,
) -> dict[str, str | None]:
    cleaned_id = _require_folder_id(folder_id)
    cleaned_name = (name or "").strip()
    if not cleaned_name or len(cleaned_name) > 80:
        raise HTTPException(status_code=400, detail="Invalid folder name")

    cleaned_parent = (parent_id or "").strip() or None
    if cleaned_parent is not None:
        cleaned_parent = _require_folder_id(cleaned_parent)
        if cleaned_parent == cleaned_id:
            raise HTTPException(status_code=400, detail="Folder cannot contain itself")

    existing = db.get(NoteFolderDB, cleaned_id)
    if existing is not None and existing.user_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden")

    owned = {folder.id: folder.parent_id for folder in _owned_folders(db, user_id)}
    if cleaned_parent is not None and cleaned_parent not in owned:
        raise HTTPException(status_code=400, detail="Parent folder not found")
    owned[cleaned_id] = cleaned_parent
    if _parent_creates_cycle(owned, cleaned_id, cleaned_parent):
        raise HTTPException(status_code=400, detail="Folder cycle")

    if existing is None:
        folder = NoteFolderDB(
            id=cleaned_id,
            user_id=user_id,
            name=cleaned_name,
            parent_id=cleaned_parent,
            created_at=_parse_created_at(created_at),
        )
    else:
        folder = existing
        folder.name = cleaned_name
        folder.parent_id = cleaned_parent
    db.add(folder)
    db.commit()
    db.refresh(folder)
    return folder.to_dict()


def delete_folder_tree(db: Session, user_id: str, folder_id: str) -> None:
    cleaned_id = _require_folder_id(folder_id)
    folder = db.get(NoteFolderDB, cleaned_id)
    if folder is None:
        return
    if folder.user_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden")

    owned = _owned_folders(db, user_id)
    parent_by_id = {item.id: item.parent_id for item in owned}
    ids = collect_subtree_ids(parent_by_id, cleaned_id)
    destination = folder.parent_id

    notes = list(
        db.scalars(
            select(NoteDB).where(
                NoteDB.user_id == user_id,
                NoteDB.folder_id.in_(ids),
            )
        ).all()
    )
    for note in notes:
        note.folder_id = destination
        note.folder_assigned = True
        db.add(note)

    for item in owned:
        if item.id in ids:
            db.delete(item)
    db.commit()


def set_note_folder(
    db: Session,
    user_id: str,
    note_id: str,
    folder_id: str | None,
) -> None:
    note = db.get(NoteDB, note_id)
    if note is None:
        raise HTTPException(status_code=404, detail="Note not found")
    if note.user_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden")

    cleaned = (folder_id or "").strip() or None
    if cleaned is not None:
        cleaned = _require_folder_id(cleaned)
        folder = db.get(NoteFolderDB, cleaned)
        if folder is None or folder.user_id != user_id:
            raise HTTPException(status_code=400, detail="Folder not found")

    note.folder_id = cleaned
    note.folder_assigned = True
    db.add(note)
    db.commit()
