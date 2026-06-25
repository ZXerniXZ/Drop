import json
import uuid
from pathlib import Path
from typing import Any

from fastapi import Depends, FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

import config  # noqa: F401
from auth import get_current_user
from database import Base, engine, get_db
from models.note import NoteDB  # noqa: F401
from services.chat_service import NoteChatRequest, stream_note_chat
from services.job_service import get_job, start_upload_job

STORAGE_DIR = Path(__file__).parent / "storage"

app = FastAPI(title="Drop Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def init_db():
    Base.metadata.create_all(bind=engine)


def _parse_tags_list(available_tags: str | None) -> list[str] | None:
    if not available_tags or not available_tags.strip():
        return None
    try:
        parsed = json.loads(available_tags)
        if isinstance(parsed, list):
            return [str(t).strip() for t in parsed if str(t).strip()]
    except json.JSONDecodeError:
        return None
    return None


def _get_owned_note(db: Session, note_id: str, user_id: str) -> NoteDB:
    note = db.get(NoteDB, note_id)
    if note is None:
        raise HTTPException(status_code=404, detail="Note not found")
    if note.user_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    return note


@app.post("/upload-audio")
async def upload_audio(
    current_user_id: str = Depends(get_current_user),
    file: UploadFile = File(...),
    ai_model: str | None = Form(default=None),
    language: str | None = Form(default=None),
    custom_prompt: str | None = Form(default=None),
    available_tags: str | None = Form(default=None),
):
    STORAGE_DIR.mkdir(parents=True, exist_ok=True)

    original_name = Path(file.filename or "audio").name
    suffix = Path(original_name).suffix or ".m4a"
    saved_name = f"{uuid.uuid4()}{suffix}"
    destination = STORAGE_DIR / saved_name

    content = await file.read()
    destination.write_bytes(content)

    job_id = str(uuid.uuid4())
    start_upload_job(
        job_id,
        user_id=current_user_id,
        file_path=str(destination),
        saved_name=saved_name,
        ai_model=ai_model,
        language=language,
        custom_prompt=custom_prompt,
        available_tags=_parse_tags_list(available_tags),
    )

    return {
        "success": True,
        "job_id": job_id,
        "status": "processing",
    }


@app.get("/jobs/{job_id}")
async def get_upload_job(
    job_id: str,
    current_user_id: str = Depends(get_current_user),
):
    job = get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")
    if job.get("user_id") != current_user_id:
        raise HTTPException(status_code=403, detail="Forbidden")

    response: dict[str, Any] = {
        "job_id": job_id,
        "status": job["status"],
    }
    if job.get("note_id"):
        response["note_id"] = job["note_id"]
    if job.get("error"):
        response["error"] = job["error"]
    if job.get("result"):
        response["result"] = job["result"]
    return response


@app.get("/notes")
async def list_notes(
    current_user_id: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    stmt = (
        select(NoteDB)
        .where(NoteDB.user_id == current_user_id)
        .order_by(NoteDB.created_at.desc())
    )
    notes = db.scalars(stmt).all()
    return [note.to_result_dict() for note in notes]


@app.get("/notes/{note_id}")
async def get_note(
    note_id: str,
    current_user_id: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    note = _get_owned_note(db, note_id, current_user_id)
    return note.to_result_dict()


@app.post("/chat-note/stream")
async def chat_note_stream(
    request: NoteChatRequest,
    current_user_id: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _get_owned_note(db, request.note_id, current_user_id)
    return StreamingResponse(
        stream_note_chat(request),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
