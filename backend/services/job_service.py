import asyncio
import uuid
from datetime import datetime, timezone
from typing import Any

from database import SessionLocal
from models.note import NoteDB
from services.llm_service import process_transcript
from services.openrouter_service import transcribe_audio

_jobs: dict[str, dict[str, Any]] = {}
_MAX_JOBS = 200


def _prune_jobs() -> None:
    if len(_jobs) <= _MAX_JOBS:
        return
    oldest = sorted(
        _jobs.items(),
        key=lambda item: item[1].get("created_at", ""),
    )
    for job_id, _ in oldest[: len(_jobs) - _MAX_JOBS]:
        _jobs.pop(job_id, None)


def create_job(job_id: str, *, user_id: str) -> None:
    _prune_jobs()
    _jobs[job_id] = {
        "status": "processing",
        "user_id": user_id,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "result": None,
        "error": None,
        "note_id": None,
    }


def get_job(job_id: str) -> dict[str, Any] | None:
    return _jobs.get(job_id)


def _save_note_to_db(
    user_id: str,
    saved_name: str,
    transcription: str,
    processed: dict[str, Any],
) -> str:
    note_id = str(uuid.uuid4())
    db = SessionLocal()
    try:
        note = NoteDB(
            id=note_id,
            user_id=user_id,
            title=processed["title"],
            summary=processed["summary"],
            formatted_transcription=processed["formatted_transcript"],
            raw_transcription=transcription,
            highlights=processed["highlights"],
            key_data=processed["key_data"],
            speaker_view=processed["speaker_view"],
            audio_filename=saved_name,
        )
        db.add(note)
        db.commit()
        return note_id
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


async def run_upload_job(
    job_id: str,
    *,
    user_id: str,
    file_path: str,
    saved_name: str,
    ai_model: str | None,
    language: str | None,
    custom_prompt: str | None,
    available_tags: list[str] | None,
) -> None:
    try:
        transcription = await transcribe_audio(file_path, language=language)
        processed = await process_transcript(
            transcription,
            model=ai_model,
            custom_prompt=custom_prompt,
            language=language,
            available_tags=available_tags,
        )
        note_id = _save_note_to_db(user_id, saved_name, transcription, processed)
        result = {
            "success": True,
            "note_id": note_id,
            "filename": saved_name,
            "raw_transcription": transcription,
            "title": processed["title"],
            "formatted_transcription": processed["formatted_transcript"],
            "summary": processed["summary"],
            "highlights": processed["highlights"],
            "key_data": processed["key_data"],
            "speaker_view": processed["speaker_view"],
        }
        _jobs[job_id] = {
            "status": "completed",
            "user_id": user_id,
            "created_at": _jobs[job_id]["created_at"],
            "result": result,
            "error": None,
            "note_id": note_id,
        }
    except Exception as exc:
        _jobs[job_id] = {
            "status": "failed",
            "user_id": user_id,
            "created_at": _jobs.get(job_id, {}).get(
                "created_at", datetime.now(timezone.utc).isoformat()
            ),
            "result": None,
            "error": str(exc),
            "note_id": None,
        }


def start_upload_job(
    job_id: str,
    *,
    user_id: str,
    file_path: str,
    saved_name: str,
    ai_model: str | None,
    language: str | None,
    custom_prompt: str | None,
    available_tags: list[str] | None,
) -> None:
    create_job(job_id, user_id=user_id)
    asyncio.create_task(
        run_upload_job(
            job_id,
            user_id=user_id,
            file_path=file_path,
            saved_name=saved_name,
            ai_model=ai_model,
            language=language,
            custom_prompt=custom_prompt,
            available_tags=available_tags,
        )
    )
