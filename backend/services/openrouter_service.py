import asyncio
import base64
from pathlib import Path

import httpx

from config import OPENROUTER_API_KEY, TRANSCRIPTION_TIMEOUT_SECONDS

OPENROUTER_TRANSCRIPTIONS_URL = "https://openrouter.ai/api/v1/audio/transcriptions"
WHISPER_MODEL = "openai/whisper-large-v3"
APP_REFERER = "https://github.com/ZXerniXZ/Drop"
APP_TITLE = "Drop"

LANGUAGE_CODES = {
    "italian": "it",
    "italiano": "it",
    "english": "en",
    "inglese": "en",
    "automatic": None,
    "automatico": None,
}

_FORMAT_MAP = {
    ".m4a": "m4a",
    ".mp3": "mp3",
    ".wav": "wav",
    ".flac": "flac",
    ".ogg": "ogg",
    ".webm": "webm",
    ".aac": "aac",
}


def _audio_format(file_path: str) -> str:
    suffix = Path(file_path).suffix.lower()
    return _FORMAT_MAP.get(suffix, "m4a")


def _build_transcription_payload(
    path: Path, language: str | None, *, verbose: bool
) -> tuple[dict[str, str], dict]:
    audio_b64 = base64.b64encode(path.read_bytes()).decode("ascii")

    headers = {
        "Authorization": f"Bearer {OPENROUTER_API_KEY}",
        "Content-Type": "application/json",
        "HTTP-Referer": APP_REFERER,
        "X-Title": APP_TITLE,
    }

    payload: dict = {
        "model": WHISPER_MODEL,
        "input_audio": {
            "data": audio_b64,
            "format": _audio_format(str(path)),
        },
    }

    if verbose:
        payload["response_format"] = "verbose_json"
        payload["timestamp_granularities"] = ["segment", "word"]

    if language:
        lang_key = language.strip().lower()
        lang_code = LANGUAGE_CODES.get(lang_key, lang_key if len(lang_key) == 2 else None)
        if lang_code:
            payload["language"] = lang_code

    return headers, payload


async def _request_transcription(
    file_path: str, language: str | None, *, verbose: bool
) -> dict:
    if not OPENROUTER_API_KEY:
        raise ValueError("OPENROUTER_API_KEY is not configured")

    path = Path(file_path)
    headers, payload = await asyncio.to_thread(
        _build_transcription_payload, path, language, verbose=verbose
    )

    timeout = httpx.Timeout(
        TRANSCRIPTION_TIMEOUT_SECONDS,
        connect=30.0,
    )
    async with httpx.AsyncClient(timeout=timeout) as client:
        response = await client.post(
            OPENROUTER_TRANSCRIPTIONS_URL,
            json=payload,
            headers=headers,
        )
        response.raise_for_status()
        data = response.json()

    if not data.get("text"):
        raise ValueError("OpenRouter returned an empty transcription")

    return data


async def transcribe_audio(file_path: str, language: str | None = None) -> str:
    data = await _request_transcription(file_path, language, verbose=False)
    return data["text"]


async def transcribe_audio_verbose(
    file_path: str, language: str | None = None
) -> dict:
    """Trascrizione con timestamp reali per segmento e per parola.

    I timestamp sono relativi all'inizio del file passato: chi lavora su
    spezzoni deve applicare l'offset del segmento.
    """
    data = await _request_transcription(file_path, language, verbose=True)
    return {
        "text": data["text"],
        "duration": data.get("duration"),
        "segments": data.get("segments") or [],
        "words": data.get("words") or [],
    }
