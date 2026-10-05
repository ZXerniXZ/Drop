import json
import uuid
from pathlib import Path
from typing import Any

import asyncio
from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, StreamingResponse
from starlette.background import BackgroundTask
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

import config  # noqa: F401
from auth import get_current_user
from database import Base, engine, ensure_schema, get_db
from models.deleted_note import DeletedNoteDB  # noqa: F401
from models.note import NoteDB  # noqa: F401
from models.note_share import NoteShareDB  # noqa: F401
from models.job import JobDB  # noqa: F401
from models.server_usage import UserServerUsage  # noqa: F401
from models.upload_session import (  # noqa: F401
    CHUNK_SIZE,
    LEGACY_UPLOAD_MAX_BYTES,
    UploadSessionDB,
)
from services.account_service import (
    build_export_zip,
    delete_auth_user,
    ensure_can_delete_account,
    purge_user_data,
    remove_export_file,
)
from services.app_version import AppVersionMiddleware, version_payload
from services.chat_service import NoteChatRequest, stream_note_chat
from services.job_service import (
    get_job,
    list_active_jobs,
    start_optional_analysis_job,
    start_upload_job,
)
from services.llm_service import ANALYSIS_KINDS
from services.language_detect_service import detect_language_from_audio
from services.note_deletion import delete_note_for_user
from services.quota_service import raise_if_cannot_accept, usage_snapshot
from services.share_service import (
    claim_share,
    create_or_reuse_share,
    get_active_share,
    revoke_share,
    upsert_published_note,
)
from services.upload_session_service import (
    cleanup_expired_sessions,
    complete_session,
    create_session,
    delete_session,
    get_owned_assembled,
    get_session_status,
    register_completed_upload,
    save_chunk,
)

STORAGE_DIR = Path(__file__).parent / "storage"

AUDIO_MEDIA_TYPES = {
    ".m4a": "audio/mp4",
    ".mp3": "audio/mpeg",
    ".wav": "audio/wav",
    ".aac": "audio/aac",
    ".ogg": "audio/ogg",
    ".webm": "audio/webm",
    ".flac": "audio/flac",
}

app = FastAPI(title="Drop Backend")

app.add_middleware(AppVersionMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=config.CORS_ORIGIN_REGEX,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class NoteAnalysisRequest(BaseModel):
    ai_model: str | None = None
    output_language: str | None = None
    custom_prompt: str | None = None
    available_tags: list[str] | None = None
    openrouter_api_key: str | None = Field(default=None, max_length=256)


class NoteReanalyzeRequest(BaseModel):
    ai_model: str | None = None
    language: str | None = None
    source_language: str | None = None
    output_language: str | None = None
    custom_prompt: str | None = None
    available_tags: list[str] | None = None
    noise_reduction: bool | None = None
    openrouter_api_key: str | None = Field(default=None, max_length=256)


class AnalyzeUploadRequest(BaseModel):
    note_id: str | None = None
    ai_model: str | None = None
    language: str | None = None
    source_language: str | None = None
    output_language: str | None = None
    custom_prompt: str | None = None
    available_tags: list[str] | None = None
    duration_seconds: float | None = Field(default=None, ge=0)
    noise_reduction: bool | None = None
    openrouter_api_key: str | None = Field(default=None, max_length=256)


class NotePublishRequest(BaseModel):
    note_id: str
    upload_id: str | None = None
    title: str = ""
    summary: str = ""
    formatted_transcription: str = ""
    raw_transcription: str = ""
    highlights: list[str] = Field(default_factory=list)
    key_data: dict[str, Any] = Field(default_factory=dict)
    speaker_view: list[dict[str, Any]] = Field(default_factory=list)
    analysis_state: dict[str, Any] | None = None
    transcript_segments: list[dict[str, Any]] = Field(default_factory=list)
    audio_duration: float | None = None
    source_language: str | None = None
    output_language: str | None = None


class UploadSessionCreate(BaseModel):
    filename: str = "audio.m4a"
    total_size: int = Field(gt=0)
    total_chunks: int = Field(gt=0)
    note_id: str | None = None
    ai_model: str | None = None
    language: str | None = None
    source_language: str | None = None
    output_language: str | None = None
    custom_prompt: str | None = None
    available_tags: list[str] | None = None
    duration_seconds: float | None = Field(default=None, ge=0)
    defer_analysis: bool = False
    noise_reduction: bool = False


@app.on_event("startup")
def init_db():
    Base.metadata.create_all(bind=engine)
    ensure_schema()
    cleanup_expired_sessions()


def _as_bool(value: object) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return False


def _noise_reduction_flag(explicit: bool | None, metadata: dict[str, Any] | None) -> bool:
    if explicit is not None:
        return explicit
    if not metadata:
        return False
    return _as_bool(metadata.get("noise_reduction"))


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


def _metadata_from_body(body: UploadSessionCreate) -> dict[str, Any]:
    return {
        "note_id": body.note_id,
        "ai_model": body.ai_model,
        "language": body.language,
        "source_language": body.source_language,
        "output_language": body.output_language,
        "custom_prompt": body.custom_prompt,
        "available_tags": body.available_tags,
        "duration_seconds": body.duration_seconds,
        "defer_analysis": body.defer_analysis,
        "noise_reduction": body.noise_reduction,
    }


def _get_owned_note(db: Session, note_id: str, user_id: str) -> NoteDB:
    note = db.get(NoteDB, note_id)
    if note is None:
        raise HTTPException(status_code=404, detail="Note not found")
    if note.user_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    return note


def _note_audio_path(note: NoteDB) -> Path | None:
    if not note.audio_filename:
        return None
    # Il nome arriva dal database, ma resta confinato a STORAGE_DIR per sicurezza.
    path = STORAGE_DIR / Path(note.audio_filename).name
    return path if path.is_file() else None


def _start_analysis_job(
    *,
    user_id: str,
    note_id: str | None,
    file_path: str,
    saved_name: str,
    ai_model: str | None,
    language: str | None,
    source_language: str | None,
    output_language: str | None,
    custom_prompt: str | None,
    available_tags: list[str] | None,
    estimated_seconds: float | None,
    openrouter_api_key: str | None = None,
    noise_reduction: bool = False,
) -> str:
    job_id = str(uuid.uuid4())
    start_upload_job(
        job_id,
        user_id=user_id,
        note_id=note_id,
        file_path=file_path,
        saved_name=saved_name,
        ai_model=ai_model,
        language=language,
        custom_prompt=custom_prompt,
        available_tags=available_tags,
        estimated_seconds=estimated_seconds,
        source_language=source_language,
        output_language=output_language,
        openrouter_api_key=openrouter_api_key,
        noise_reduction=noise_reduction,
    )
    return job_id


async def _detect_owned_audio(
    file_path: str, *, denoise: bool = False
) -> dict[str, Any]:
    try:
        detected = await detect_language_from_audio(file_path, denoise=denoise)
    except Exception:
        detected = None
    return {
        "detected_language": detected,
        "source_language": detected or "automatic",
        "output_language": detected,
    }


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/account/export")
async def export_account(
    current_user_id: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    zip_path = build_export_zip(db, current_user_id)
    return FileResponse(
        zip_path,
        media_type="application/zip",
        filename="drop-dati.zip",
        background=BackgroundTask(remove_export_file, str(zip_path)),
    )


@app.delete("/account")
async def delete_account(
    current_user_id: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    ensure_can_delete_account(current_user_id)
    purge_user_data(db, current_user_id)
    await delete_auth_user(current_user_id)
    return {"success": True}


@app.get("/app/version")
async def app_version():
    return version_payload()


@app.get("/usage/quota")
async def read_server_quota(
    current_user_id: str = Depends(get_current_user),
):
    return usage_snapshot(current_user_id)


@app.post("/upload-audio/sessions")
async def create_upload_session(
    body: UploadSessionCreate,
    current_user_id: str = Depends(get_current_user),
):
    if not body.defer_analysis:
        raise_if_cannot_accept(current_user_id, body.duration_seconds)
    session = create_session(
        user_id=current_user_id,
        filename=body.filename,
        total_size=body.total_size,
        total_chunks=body.total_chunks,
        metadata=_metadata_from_body(body),
    )
    status = session.to_status_dict()
    return {
        "upload_id": status["upload_id"],
        "chunk_size": CHUNK_SIZE,
        "total_chunks": status["total_chunks"],
        "total_size": status["total_size"],
    }


@app.get("/upload-audio/sessions/{upload_id}")
async def read_upload_session(
    upload_id: str,
    current_user_id: str = Depends(get_current_user),
):
    return get_session_status(upload_id, user_id=current_user_id)


@app.put("/upload-audio/sessions/{upload_id}/chunks/{index}")
async def upload_chunk(
    upload_id: str,
    index: int,
    request: Request,
    current_user_id: str = Depends(get_current_user),
):
    data = await request.body()
    return save_chunk(
        upload_id,
        user_id=current_user_id,
        index=index,
        data=data,
    )


@app.post("/upload-audio/sessions/{upload_id}/complete")
async def complete_upload_session(
    upload_id: str,
    current_user_id: str = Depends(get_current_user),
):
    saved_name, file_path, metadata = await asyncio.to_thread(
        complete_session,
        upload_id,
        user_id=current_user_id,
    )
    if not metadata.get("defer_analysis"):
        raise_if_cannot_accept(current_user_id, metadata.get("duration_seconds"))
    if metadata.get("defer_analysis"):
        return {
            "success": True,
            "status": "uploaded",
            "upload_id": upload_id,
            "saved_name": saved_name,
            "note_id": metadata.get("note_id"),
        }
    job_id = _start_analysis_job(
        user_id=current_user_id,
        note_id=metadata.get("note_id"),
        file_path=file_path,
        saved_name=saved_name,
        ai_model=metadata.get("ai_model"),
        language=metadata.get("language"),
        source_language=metadata.get("source_language"),
        output_language=metadata.get("output_language"),
        custom_prompt=metadata.get("custom_prompt"),
        available_tags=metadata.get("available_tags"),
        estimated_seconds=metadata.get("duration_seconds"),
        noise_reduction=_as_bool(metadata.get("noise_reduction")),
    )
    return {
        "success": True,
        "job_id": job_id,
        "status": "processing",
        "upload_id": upload_id,
        "saved_name": saved_name,
    }


@app.delete("/upload-audio/sessions/{upload_id}")
async def cancel_upload_session(
    upload_id: str,
    current_user_id: str = Depends(get_current_user),
):
    delete_session(upload_id, user_id=current_user_id)
    return {"success": True}


@app.post("/upload-audio")
async def upload_audio(
    current_user_id: str = Depends(get_current_user),
    file: UploadFile = File(...),
    ai_model: str | None = Form(default=None),
    language: str | None = Form(default=None),
    source_language: str | None = Form(default=None),
    output_language: str | None = Form(default=None),
    custom_prompt: str | None = Form(default=None),
    available_tags: str | None = Form(default=None),
    note_id: str | None = Form(default=None),
    duration_seconds: float | None = Form(default=None),
    defer_analysis: bool = Form(default=False),
    noise_reduction: str | None = Form(default=None),
):
    if not defer_analysis:
        raise_if_cannot_accept(current_user_id, duration_seconds)
    STORAGE_DIR.mkdir(parents=True, exist_ok=True)

    original_name = Path(file.filename or "audio").name
    suffix = Path(original_name).suffix or ".m4a"
    saved_name = f"{uuid.uuid4()}{suffix}"
    destination = STORAGE_DIR / saved_name

    content = await file.read()
    if len(content) > LEGACY_UPLOAD_MAX_BYTES:
        raise HTTPException(
            status_code=413,
            detail=(
                f"File exceeds legacy upload limit ({LEGACY_UPLOAD_MAX_BYTES} bytes). "
                "Use chunked upload sessions."
            ),
        )
    await asyncio.to_thread(destination.write_bytes, content)

    metadata = {
        "note_id": note_id,
        "ai_model": ai_model,
        "language": language,
        "source_language": source_language,
        "output_language": output_language,
        "custom_prompt": custom_prompt,
        "available_tags": _parse_tags_list(available_tags),
        "duration_seconds": duration_seconds,
        "defer_analysis": defer_analysis,
        "noise_reduction": _as_bool(noise_reduction),
    }
    session = register_completed_upload(
        user_id=current_user_id,
        filename=original_name,
        file_path=str(destination),
        total_size=len(content),
        metadata=metadata,
    )

    if defer_analysis:
        return {
            "success": True,
            "status": "uploaded",
            "upload_id": session.id,
            "saved_name": saved_name,
            "note_id": note_id,
        }

    job_id = _start_analysis_job(
        user_id=current_user_id,
        note_id=note_id,
        file_path=str(destination),
        saved_name=saved_name,
        ai_model=ai_model,
        language=language,
        source_language=source_language,
        output_language=output_language,
        custom_prompt=custom_prompt,
        available_tags=_parse_tags_list(available_tags),
        estimated_seconds=duration_seconds,
        noise_reduction=_as_bool(noise_reduction),
    )

    return {
        "success": True,
        "job_id": job_id,
        "status": "processing",
        "upload_id": session.id,
        "saved_name": saved_name,
    }


@app.get("/jobs/active")
async def list_upload_jobs(
    current_user_id: str = Depends(get_current_user),
):
    return list_active_jobs(current_user_id)


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

    response = dict(job)
    response.pop("user_id", None)
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


@app.delete("/notes/{note_id}")
async def delete_note(
    note_id: str,
    current_user_id: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    delete_note_for_user(db, note_id, current_user_id)
    return {"success": True}


@app.get("/notes/{note_id}")
async def get_note(
    note_id: str,
    current_user_id: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    note = _get_owned_note(db, note_id, current_user_id)
    return note.to_result_dict()


@app.get("/notes/{note_id}/audio")
async def get_note_audio(
    note_id: str,
    current_user_id: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    note = _get_owned_note(db, note_id, current_user_id)
    path = _note_audio_path(note)
    if path is None:
        raise HTTPException(status_code=404, detail="Audio file not available")
    return FileResponse(
        path,
        media_type=AUDIO_MEDIA_TYPES.get(path.suffix.lower(), "application/octet-stream"),
        filename=path.name,
    )


@app.post("/notes/{note_id}/analyses/{kind}")
async def start_note_analysis(
    note_id: str,
    kind: str,
    body: NoteAnalysisRequest,
    current_user_id: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if kind not in ANALYSIS_KINDS:
        raise HTTPException(status_code=404, detail="Unknown analysis")
    note = _get_owned_note(db, note_id, current_user_id)
    transcript = (note.raw_transcription or note.formatted_transcription or "").strip()
    if not transcript:
        raise HTTPException(status_code=409, detail="Trascrizione mancante")
    job_id = str(uuid.uuid4())
    start_optional_analysis_job(
        job_id,
        user_id=current_user_id,
        note_id=note.id,
        kind=kind,
        ai_model=body.ai_model,
        custom_prompt=body.custom_prompt,
        available_tags=body.available_tags,
        output_language=body.output_language or note.output_language,
        openrouter_api_key=body.openrouter_api_key,
    )
    return {
        "success": True,
        "job_id": job_id,
        "status": "processing",
        "note_id": note.id,
        "kind": kind,
    }


@app.post("/notes/{note_id}/reanalyze")
async def reanalyze_note(
    note_id: str,
    body: NoteReanalyzeRequest,
    current_user_id: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    note = _get_owned_note(db, note_id, current_user_id)
    path = _note_audio_path(note)
    if path is None:
        raise HTTPException(
            status_code=409,
            detail="Audio file no longer on the server: cannot re-transcribe",
        )

    if not (note.source_share_token or "").strip() and not (
        body.openrouter_api_key or ""
    ).strip():
        raise_if_cannot_accept(current_user_id, note.audio_duration)
    job_id = _start_analysis_job(
        user_id=current_user_id,
        note_id=note.id,
        file_path=str(path),
        saved_name=note.audio_filename,
        ai_model=body.ai_model,
        language=body.language,
        source_language=body.source_language,
        output_language=body.output_language,
        custom_prompt=body.custom_prompt,
        available_tags=body.available_tags,
        estimated_seconds=note.audio_duration,
        openrouter_api_key=body.openrouter_api_key,
        noise_reduction=_noise_reduction_flag(body.noise_reduction, None),
    )
    return {
        "success": True,
        "job_id": job_id,
        "status": "processing",
        "note_id": note.id,
    }


@app.post("/upload-audio/sessions/{upload_id}/detect-language")
async def detect_upload_language(
    upload_id: str,
    noise_reduction: str | None = None,
    current_user_id: str = Depends(get_current_user),
):
    _saved_name, file_path, metadata = get_owned_assembled(
        upload_id, user_id=current_user_id
    )
    denoise = (
        _as_bool(noise_reduction)
        if noise_reduction is not None
        else _as_bool(metadata.get("noise_reduction"))
    )
    return await _detect_owned_audio(file_path, denoise=denoise)


@app.post("/upload-audio/sessions/{upload_id}/analyze")
async def analyze_uploaded_audio(
    upload_id: str,
    body: AnalyzeUploadRequest,
    current_user_id: str = Depends(get_current_user),
):
    saved_name, file_path, metadata = get_owned_assembled(
        upload_id, user_id=current_user_id
    )
    duration = body.duration_seconds
    if duration is None:
        duration = metadata.get("duration_seconds")
    if not (body.openrouter_api_key or "").strip():
        raise_if_cannot_accept(current_user_id, duration)
    job_id = _start_analysis_job(
        user_id=current_user_id,
        note_id=body.note_id or metadata.get("note_id"),
        file_path=file_path,
        saved_name=saved_name,
        ai_model=body.ai_model or metadata.get("ai_model"),
        language=body.language or metadata.get("language"),
        source_language=body.source_language or metadata.get("source_language"),
        output_language=body.output_language or metadata.get("output_language"),
        custom_prompt=body.custom_prompt or metadata.get("custom_prompt"),
        available_tags=body.available_tags or metadata.get("available_tags"),
        estimated_seconds=duration,
        openrouter_api_key=body.openrouter_api_key,
        noise_reduction=_noise_reduction_flag(
            body.noise_reduction, metadata
        ),
    )
    return {
        "success": True,
        "job_id": job_id,
        "status": "processing",
        "upload_id": upload_id,
        "note_id": body.note_id or metadata.get("note_id"),
    }


@app.post("/notes/{note_id}/detect-language")
async def detect_note_language(
    note_id: str,
    noise_reduction: str | None = None,
    current_user_id: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    note = _get_owned_note(db, note_id, current_user_id)
    path = _note_audio_path(note)
    if path is None:
        raise HTTPException(status_code=404, detail="Audio file not available")
    result = await _detect_owned_audio(
        str(path), denoise=_as_bool(noise_reduction)
    )
    if result.get("output_language") is None and note.output_language:
        result["output_language"] = note.output_language
    return result


@app.get("/notes/{note_id}/share")
async def read_note_share(
    note_id: str,
    current_user_id: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    note = _get_owned_note(db, note_id, current_user_id)
    share = get_active_share(db, note.id, current_user_id)
    if share is None:
        return {"active": False, "token": None}
    return {"active": True, "token": share.token}


@app.post("/notes/{note_id}/share")
async def create_note_share(
    note_id: str,
    current_user_id: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    note = _get_owned_note(db, note_id, current_user_id)
    share = create_or_reuse_share(db, note, current_user_id)
    return {"success": True, "token": share.token, "active": True}


@app.delete("/notes/{note_id}/share")
async def delete_note_share(
    note_id: str,
    current_user_id: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    note = _get_owned_note(db, note_id, current_user_id)
    revoked = revoke_share(db, note, current_user_id)
    return {"success": True, "revoked": revoked}


@app.post("/shares/{token}/claim")
async def claim_shared_note(
    token: str,
    current_user_id: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    note, already = claim_share(db, token, current_user_id)
    payload = note.to_result_dict()
    payload["already_owned"] = already
    return payload


@app.post("/notes/publish")
async def publish_note(
    body: NotePublishRequest,
    current_user_id: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    audio_filename = ""
    if body.upload_id:
        saved_name, _path, _metadata = get_owned_assembled(
            body.upload_id, user_id=current_user_id
        )
        audio_filename = saved_name
    note = upsert_published_note(
        db,
        user_id=current_user_id,
        note_id=body.note_id,
        payload=body.model_dump(),
        audio_filename=audio_filename,
    )
    return note.to_result_dict()


@app.post("/chat-note/stream")
async def chat_note_stream(
    request: NoteChatRequest,
    current_user_id: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    note = db.get(NoteDB, request.note_id)
    if note is not None and note.user_id != current_user_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    if not request.output_language and note is not None:
        request.output_language = note.output_language
    return StreamingResponse(
        stream_note_chat(request),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
