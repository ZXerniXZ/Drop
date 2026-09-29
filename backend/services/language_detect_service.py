import subprocess
import tempfile
from pathlib import Path

from services.languages import resolve_detected
from services.openrouter_service import transcribe_audio_verbose

DETECT_CLIP_SECONDS = 20


def extract_audio_clip(source: Path, seconds: float = DETECT_CLIP_SECONDS) -> Path:
    tmp = tempfile.NamedTemporaryFile(suffix=".m4a", delete=False)
    tmp.close()
    dest = Path(tmp.name)
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        str(source),
        "-t",
        str(seconds),
        "-ac",
        "1",
        "-ar",
        "16000",
        "-c:a",
        "aac",
        "-b:a",
        "64k",
        "-y",
        str(dest),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0 or not dest.is_file() or dest.stat().st_size == 0:
        dest.unlink(missing_ok=True)
        raise RuntimeError(
            f"ffmpeg clip failed: {result.stderr.strip() or result.stdout.strip()}"
        )
    return dest


async def detect_language_from_audio(file_path: str) -> str | None:
    """Rileva la lingua dai primi secondi. Non scala la quota."""
    source = Path(file_path)
    if not source.is_file():
        raise FileNotFoundError(f"Audio file not found: {file_path}")

    clip: Path | None = None
    try:
        clip = await _extract_clip_async(source)
        verbose = await transcribe_audio_verbose(str(clip), language=None)
        raw = verbose.get("language")
        return resolve_detected(str(raw) if raw else None)
    finally:
        if clip is not None:
            clip.unlink(missing_ok=True)


async def _extract_clip_async(source: Path) -> Path:
    import asyncio

    return await asyncio.to_thread(extract_audio_clip, source)
