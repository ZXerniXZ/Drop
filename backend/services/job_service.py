import asyncio
from datetime import datetime, timezone
from typing import Any

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


def create_job(job_id: str) -> None:
    _prune_jobs()
    _jobs[job_id] = {
        "status": "processing",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "result": None,
        "error": None,
    }


def get_job(job_id: str) -> dict[str, Any] | None:
    return _jobs.get(job_id)


async def run_upload_job(
    job_id: str,
    *,
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
        _jobs[job_id] = {
            "status": "completed",
            "created_at": _jobs[job_id]["created_at"],
            "result": {
                "success": True,
                "filename": saved_name,
                "raw_transcription": transcription,
                "title": processed["title"],
                "formatted_transcription": processed["formatted_transcript"],
                "summary": processed["summary"],
                "highlights": processed["highlights"],
                "key_data": processed["key_data"],
                "speaker_view": processed["speaker_view"],
            },
            "error": None,
        }
    except Exception as exc:
        _jobs[job_id] = {
            "status": "failed",
            "created_at": _jobs.get(job_id, {}).get(
                "created_at", datetime.now(timezone.utc).isoformat()
            ),
            "result": None,
            "error": str(exc),
        }


def start_upload_job(
    job_id: str,
    *,
    file_path: str,
    saved_name: str,
    ai_model: str | None,
    language: str | None,
    custom_prompt: str | None,
    available_tags: list[str] | None,
) -> None:
    create_job(job_id)
    asyncio.create_task(
        run_upload_job(
            job_id,
            file_path=file_path,
            saved_name=saved_name,
            ai_model=ai_model,
            language=language,
            custom_prompt=custom_prompt,
            available_tags=available_tags,
        )
    )
