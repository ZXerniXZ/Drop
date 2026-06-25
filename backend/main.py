import json
import uuid
from pathlib import Path
from typing import Any

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

import config  # noqa: F401
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


@app.post("/upload-audio")
async def upload_audio(
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
async def get_upload_job(job_id: str):
    job = get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")

    response: dict[str, Any] = {
        "job_id": job_id,
        "status": job["status"],
    }
    if job.get("error"):
        response["error"] = job["error"]
    if job.get("result"):
        response["result"] = job["result"]
    return response


@app.post("/chat-note/stream")
async def chat_note_stream(request: NoteChatRequest):
    return StreamingResponse(
        stream_note_chat(request),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
