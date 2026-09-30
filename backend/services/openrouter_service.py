import asyncio
from pathlib import Path

import httpx

from config import OPENROUTER_API_KEY, TRANSCRIPTION_TIMEOUT_SECONDS
from services.languages import whisper_code

OPENROUTER_TRANSCRIPTIONS_URL = "https://openrouter.ai/api/v1/audio/transcriptions"
WHISPER_MODEL = "openai/whisper-large-v3"
APP_REFERER = "https://github.com/ZXerniXZ/Drop"
APP_TITLE = "Drop"
# Whisper/OpenRouter rifiutano body troppo grandi. Multipart evita il +33% del JSON
# in base64, ma il file grezzo deve restare sotto questo tetto.
MAX_TRANSCRIPTION_FILE_BYTES = 20 * 1024 * 1024

_MIME_MAP = {
    ".m4a": "audio/mp4",
    ".mp3": "audio/mpeg",
    ".wav": "audio/wav",
    ".flac": "audio/flac",
    ".ogg": "audio/ogg",
    ".webm": "audio/webm",
    ".aac": "audio/aac",
}


def _mime(path: Path) -> str:
    return _MIME_MAP.get(path.suffix.lower(), "audio/mp4")


def _auth_key(api_key: str | None) -> str:
    key = (api_key or "").strip() or OPENROUTER_API_KEY
    if not key:
        raise ValueError("OPENROUTER_API_KEY is not configured")
    return key


async def _request_transcription(
    file_path: str,
    language: str | None,
    *,
    verbose: bool,
    api_key: str | None = None,
) -> dict:
    path = Path(file_path)
    if not path.is_file():
        raise FileNotFoundError(f"Audio file not found: {file_path}")

    size = path.stat().st_size
    if size > MAX_TRANSCRIPTION_FILE_BYTES:
        raise ValueError(
            f"Audio chunk too large for OpenRouter ({size} bytes). "
            "Split or transcode before transcribing."
        )

    headers = {
        "Authorization": f"Bearer {_auth_key(api_key)}",
        "HTTP-Referer": APP_REFERER,
        "X-Title": APP_TITLE,
    }
    form: list[tuple[str, str]] = [("model", WHISPER_MODEL)]
    lang_code = whisper_code(language)
    if lang_code:
        form.append(("language", lang_code))
    if verbose:
        form.append(("response_format", "verbose_json"))
        form.append(("timestamp_granularities[]", "segment"))
        form.append(("timestamp_granularities[]", "word"))

    audio_bytes = await asyncio.to_thread(path.read_bytes)
    files = {"file": (path.name, audio_bytes, _mime(path))}

    timeout = httpx.Timeout(
        TRANSCRIPTION_TIMEOUT_SECONDS,
        connect=30.0,
    )
    async with httpx.AsyncClient(timeout=timeout) as client:
        response = await client.post(
            OPENROUTER_TRANSCRIPTIONS_URL,
            headers=headers,
            data=form,
            files=files,
        )
        if response.status_code == 413:
            raise ValueError(
                "OpenRouter ha rifiutato l'audio: file troppo grande. "
                f"({size} byte)"
            )
        if response.is_error:
            raise ValueError(
                f"OpenRouter transcription error {response.status_code}: "
                f"{response.text}"
            )
        data = response.json()

    if not data.get("text"):
        raise ValueError("OpenRouter returned an empty transcription")

    return data


async def transcribe_audio(
    file_path: str,
    language: str | None = None,
    *,
    api_key: str | None = None,
) -> str:
    data = await _request_transcription(
        file_path, language, verbose=False, api_key=api_key
    )
    return data["text"]


async def transcribe_audio_verbose(
    file_path: str,
    language: str | None = None,
    *,
    api_key: str | None = None,
) -> dict:
    """Trascrizione con timestamp reali per segmento e per parola.

    I timestamp sono relativi all'inizio del file passato: chi lavora su
    spezzoni deve applicare l'offset del segmento.
    """
    data = await _request_transcription(
        file_path, language, verbose=True, api_key=api_key
    )
    return {
        "text": data["text"],
        "duration": data.get("duration"),
        "language": data.get("language"),
        "segments": data.get("segments") or [],
        "words": data.get("words") or [],
    }
