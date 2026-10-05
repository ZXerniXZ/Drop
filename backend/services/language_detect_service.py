import subprocess
import tempfile
from pathlib import Path

from services.audio_segmentation_service import (
    denoise_filter_unsupported,
    speech_filter_attempts,
)
from services.languages import resolve_detected
from services.openrouter_service import transcribe_audio_verbose

DETECT_CLIP_SECONDS = 20


def extract_audio_clip(
    source: Path,
    seconds: float = DETECT_CLIP_SECONDS,
    *,
    denoise: bool = False,
) -> Path:
    tmp = tempfile.NamedTemporaryFile(suffix=".m4a", delete=False)
    tmp.close()
    dest = Path(tmp.name)
    last_error = ""
    for index, audio_filter in enumerate(speech_filter_attempts(denoise=denoise)):
        cmd = [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            str(source),
            "-t",
            str(seconds),
            "-af",
            audio_filter,
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
        if result.returncode == 0 and dest.is_file() and dest.stat().st_size > 0:
            return dest
        last_error = (result.stderr or result.stdout or "").strip()
        dest.unlink(missing_ok=True)
        if not (index == 0 and denoise and denoise_filter_unsupported(last_error)):
            break
    raise RuntimeError(f"ffmpeg clip failed: {last_error}")


async def detect_language_from_audio(
    file_path: str, *, denoise: bool = False
) -> str | None:
    """Rileva la lingua dai primi secondi. Non scala la quota."""
    source = Path(file_path)
    if not source.is_file():
        raise FileNotFoundError(f"Audio file not found: {file_path}")

    clip: Path | None = None
    try:
        clip = await _extract_clip_async(source, denoise=denoise)
        verbose = await transcribe_audio_verbose(str(clip), language=None)
        raw = verbose.get("language")
        return resolve_detected(str(raw) if raw else None)
    finally:
        if clip is not None:
            clip.unlink(missing_ok=True)


async def _extract_clip_async(source: Path, *, denoise: bool) -> Path:
    import asyncio

    return await asyncio.to_thread(
        extract_audio_clip, source, denoise=denoise
    )
