import asyncio
import uuid
from datetime import datetime, timezone
from typing import Any

from database import SessionLocal
from models.job import JobDB
from models.note import NoteDB
from services.audio_segmentation_service import transcribe_audio_long_verbose
from services.llm_service import process_transcript


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _with_db():
    return SessionLocal()


def create_job(job_id: str, *, user_id: str) -> None:
    db = _with_db()
    try:
        db.add(
            JobDB(
                id=job_id,
                user_id=user_id,
                status="processing",
                phase="transcribing",
            )
        )
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def get_job(job_id: str) -> dict[str, Any] | None:
    db = _with_db()
    try:
        job = db.get(JobDB, job_id)
        if job is None:
            return None
        return job.to_status_dict() | {"user_id": job.user_id}
    finally:
        db.close()


def _update_job(
    job_id: str,
    *,
    status: str | None = None,
    phase: str | None = None,
    progress: dict[str, Any] | None = None,
    clear_progress: bool = False,
    result: dict[str, Any] | None = None,
    error: str | None = None,
    note_id: str | None = None,
) -> None:
    db = _with_db()
    try:
        job = db.get(JobDB, job_id)
        if job is None:
            return
        if status is not None:
            job.status = status
        if phase is not None:
            job.phase = phase
        if clear_progress:
            job.progress = None
        elif progress is not None:
            job.progress = progress
        if result is not None:
            job.result = result
        if error is not None:
            job.error = error
        if note_id is not None:
            job.note_id = note_id
        db.add(job)
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def _update_job_progress(
    job_id: str, *, phase: str, current: int | None = None, total: int | None = None
) -> None:
    progress = None
    if current is not None and total is not None and total > 0:
        progress = {
            "current": current,
            "total": total,
            "percent": round(current * 100 / total),
        }
    _update_job(job_id, phase=phase, progress=progress, clear_progress=progress is None)


def _save_note_to_db(
    user_id: str,
    saved_name: str,
    transcription: str,
    processed: dict[str, Any],
    *,
    note_id: str | None = None,
    transcript_segments: list[dict[str, Any]] | None = None,
    audio_duration: float | None = None,
) -> str:
    resolved_id = (note_id or "").strip() or str(uuid.uuid4())
    segments = transcript_segments or []
    db = _with_db()
    try:
        existing = db.get(NoteDB, resolved_id)
        if existing is not None:
            if existing.user_id != user_id:
                raise PermissionError("Note id already belongs to another user")
            existing.title = processed["title"]
            existing.summary = processed["summary"]
            existing.formatted_transcription = processed["formatted_transcript"]
            existing.raw_transcription = transcription
            existing.highlights = processed["highlights"]
            existing.key_data = processed["key_data"]
            existing.speaker_view = processed["speaker_view"]
            existing.transcript_segments = segments
            existing.audio_duration = audio_duration
            existing.audio_filename = saved_name
            db.add(existing)
            db.commit()
            return resolved_id

        note = NoteDB(
            id=resolved_id,
            user_id=user_id,
            title=processed["title"],
            summary=processed["summary"],
            formatted_transcription=processed["formatted_transcript"],
            raw_transcription=transcription,
            highlights=processed["highlights"],
            key_data=processed["key_data"],
            speaker_view=processed["speaker_view"],
            transcript_segments=segments,
            audio_duration=audio_duration,
            audio_filename=saved_name,
        )
        db.add(note)
        db.commit()
        return resolved_id
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


async def run_upload_job(
    job_id: str,
    *,
    user_id: str,
    note_id: str | None,
    file_path: str,
    saved_name: str,
    ai_model: str | None,
    language: str | None,
    custom_prompt: str | None,
    available_tags: list[str] | None,
) -> None:
    try:
        _update_job_progress(job_id, phase="transcribing")

        def on_transcribe_progress(current: int, total: int) -> None:
            _update_job_progress(
                job_id, phase="transcribing", current=current, total=total
            )

        verbose = await transcribe_audio_long_verbose(
            file_path,
            language=language,
            on_progress=on_transcribe_progress,
        )
        transcription = verbose["text"]
        transcript_segments = verbose["segments"]
        audio_duration = verbose.get("duration")

        _update_job_progress(job_id, phase="analyzing")
        processed = await process_transcript(
            transcription,
            model=ai_model,
            custom_prompt=custom_prompt,
            language=language,
            available_tags=available_tags,
            segments=transcript_segments,
        )
        note_id = _save_note_to_db(
            user_id,
            saved_name,
            transcription,
            processed,
            note_id=note_id,
            transcript_segments=transcript_segments,
            audio_duration=audio_duration,
        )
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
            "transcript_segments": transcript_segments,
            "audio_duration": audio_duration,
        }
        _update_job(
            job_id,
            status="completed",
            phase="completed",
            clear_progress=True,
            result=result,
            error=None,
            note_id=note_id,
        )
    except Exception as exc:
        _update_job(
            job_id,
            status="failed",
            phase="failed",
            clear_progress=True,
            error=str(exc),
        )


def start_upload_job(
    job_id: str,
    *,
    user_id: str,
    note_id: str | None,
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
            note_id=note_id,
            file_path=file_path,
            saved_name=saved_name,
            ai_model=ai_model,
            language=language,
            custom_prompt=custom_prompt,
            available_tags=available_tags,
        )
    )
