import uuid
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

import config  # noqa: F401
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
async def upload_audio(file: UploadFile = File(...)):
    STORAGE_DIR.mkdir(parents=True, exist_ok=True)

    original_name = Path(file.filename or "audio").name
    suffix = Path(original_name).suffix or ".m4a"
    saved_name = f"{uuid.uuid4()}{suffix}"
    destination = STORAGE_DIR / saved_name

    content = await file.read()
    destination.write_bytes(content)

    try:
        transcription = await transcribe_audio(str(destination))
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Transcription failed: {exc}",
        ) from exc

    return {
        "success": True,
        "filename": saved_name,
        "size": len(content),
        "transcription": transcription,
    }
