import uuid
from pathlib import Path
from typing import Any

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

import config  # noqa: F401
from services.chat_service import NoteChatRequest, stream_note_chat
from services.llm_service import process_transcript
from services.openrouter_service import transcribe_audio

STORAGE_DIR = Path(__file__).parent / "storage"

app = FastAPI(title="Drop Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.post("/upload-audio")
async def upload_audio(
    file: UploadFile = File(...),
    ai_model: str | None = Form(default=None),
    language: str | None = Form(default=None),
    custom_prompt: str | None = Form(default=None),
):
    STORAGE_DIR.mkdir(parents=True, exist_ok=True)

    original_name = Path(file.filename or "audio").name
    suffix = Path(original_name).suffix or ".m4a"
    saved_name = f"{uuid.uuid4()}{suffix}"
    destination = STORAGE_DIR / saved_name

    content = await file.read()
    destination.write_bytes(content)

    try:
        transcription = await transcribe_audio(str(destination), language=language)
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Transcription failed: {exc}",
        ) from exc

    try:
        processed = await process_transcript(
            transcription,
            model=ai_model,
            custom_prompt=custom_prompt,
            language=language,
        )
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"LLM processing failed: {exc}",
        ) from exc

    response: dict[str, Any] = {
        "success": True,
        "filename": saved_name,
        "raw_transcription": transcription,
        "formatted_transcription": processed["formatted_transcript"],
        "summary": processed["summary"],
        "highlights": processed["highlights"],
        "key_data": processed["key_data"],
        "speaker_view": processed["speaker_view"],
    }
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
