import asyncio
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from database import SessionLocal
from models.job import JobDB
from models.note import NoteDB
from services.audio_segmentation_service import (
    probe_duration_seconds,
    transcribe_audio_long_verbose,
)
from services.llm_service import process_transcript
from services.quota_service import QuotaExceeded, consume, refund


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _with_db():
    return SessionLocal()


def _note_came_from_share(user_id: str, note_id: str | None) -> bool:
    if not (note_id or "").strip():
        return False
    db = _with_db()
    try:
        note = db.get(NoteDB, note_id)
        if note is None or note.user_id != user_id:
            return False
        return bool((note.source_share_token or "").strip())
    finally:
        db.close()


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
    source_language: str | None = None,
    output_language: str | None = None,
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
            if source_language:
                existing.source_language = source_language
            if output_language:
                existing.output_language = output_language
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
            source_language=source_language,
            output_language=output_language,
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
    estimated_seconds: float | None = None,
    source_language: str | None = None,
    output_language: str | None = None,
    openrouter_api_key: str | None = None,
) -> None:
    billed_seconds = 0.0
    whisper_language = source_language or language
    analysis_language = output_language or language
    user_key = (openrouter_api_key or "").strip() or None
    try:
        probed = probe_duration_seconds(Path(file_path))
        to_bill = probed if probed and probed > 0 else estimated_seconds
        if (
            not user_key
            and to_bill
            and to_bill > 0
            and not _note_came_from_share(user_id, note_id)
        ):
            consume(user_id, to_bill)
            billed_seconds = to_bill

        _update_job_progress(job_id, phase="transcribing")

        def on_transcribe_progress(current: int, total: int) -> None:
            _update_job_progress(
                job_id, phase="transcribing", current=current, total=total
            )

        verbose = await transcribe_audio_long_verbose(
            file_path,
            language=whisper_language,
            on_progress=on_transcribe_progress,
            api_key=user_key,
        )
        transcription = verbose["text"]
        transcript_segments = verbose["segments"]
        audio_duration = verbose.get("duration")

        _update_job_progress(job_id, phase="analyzing")
        processed = await process_transcript(
            transcription,
            model=ai_model,
            custom_prompt=custom_prompt,
            language=analysis_language,
            available_tags=available_tags,
            segments=transcript_segments,
            api_key=user_key,
        )
        note_id = _save_note_to_db(
            user_id,
            saved_name,
            transcription,
            processed,
            note_id=note_id,
            transcript_segments=transcript_segments,
            audio_duration=audio_duration,
            source_language=whisper_language,
            output_language=analysis_language,
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
            "source_language": whisper_language,
            "output_language": analysis_language,
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
    except QuotaExceeded:
        _update_job(
            job_id,
            status="failed",
            phase="failed",
            clear_progress=True,
            error=(
                "Hai esaurito le 2 ore di trascrizione incluse. "
                "Aggiungi una chiave OpenRouter in Account."
            ),
        )
    except Exception as exc:
        if billed_seconds:
            refund(user_id, billed_seconds)
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
    estimated_seconds: float | None = None,
    source_language: str | None = None,
    output_language: str | None = None,
    openrouter_api_key: str | None = None,
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
            estimated_seconds=estimated_seconds,
            source_language=source_language,
            output_language=output_language,
            openrouter_api_key=openrouter_api_key,
        )
    )
