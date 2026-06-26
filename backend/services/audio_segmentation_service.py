import asyncio
import shutil
import subprocess
import tempfile
from collections.abc import Callable
from pathlib import Path

from services.openrouter_service import transcribe_audio

WHISPER_MAX_BYTES = 24 * 1024 * 1024
SEGMENT_TARGET_BYTES = 20 * 1024 * 1024


async def transcribe_audio_long(
    file_path: str,
    language: str | None = None,
    *,
    on_progress: Callable[[int, int], None] | None = None,
) -> str:
    path = Path(file_path)
    if not path.exists():
        raise FileNotFoundError(f"Audio file not found: {file_path}")

    if path.stat().st_size <= WHISPER_MAX_BYTES:
        return await transcribe_audio(file_path, language=language)

    segments = await asyncio.to_thread(_split_audio_file, path)
    try:
        transcripts: list[str] = []
        total = len(segments)
        for i, segment_path in enumerate(segments):
            if on_progress:
                on_progress(i + 1, total)
            text = await transcribe_audio(str(segment_path), language=language)
            if text.strip():
                transcripts.append(text.strip())
        return "\n\n".join(transcripts)
    finally:
        for segment in segments:
            segment.unlink(missing_ok=True)
        if segments:
            parent = segments[0].parent
            if parent.name.startswith("drop_segments_"):
                parent.rmdir()


def _split_audio_file(path: Path) -> list[Path]:
    file_size = path.stat().st_size
    if file_size <= WHISPER_MAX_BYTES:
        return [path]

    segment_count = max(2, (file_size + SEGMENT_TARGET_BYTES - 1) // SEGMENT_TARGET_BYTES)
    segment_seconds = _probe_duration_seconds(path)
    if segment_seconds is None or segment_seconds <= 0:
        segment_seconds = max(60.0, segment_count * 60.0)
    chunk_duration = segment_seconds / segment_count

    tmp_dir = Path(tempfile.mkdtemp(prefix="drop_segments_"))
    pattern = tmp_dir / "segment_%03d.m4a"
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        str(path),
        "-f",
        "segment",
        "-segment_time",
        str(chunk_duration),
        "-c",
        "copy",
        str(pattern),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        raise RuntimeError(
            f"ffmpeg split failed: {result.stderr.strip() or result.stdout}"
        )

    segments = sorted(tmp_dir.glob("segment_*.m4a"))
    if not segments:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        raise RuntimeError("ffmpeg produced no segments")

    oversized = [s for s in segments if s.stat().st_size > WHISPER_MAX_BYTES]
    if oversized:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        raise RuntimeError(
            "A segment still exceeds Whisper limit; reduce SEGMENT_TARGET_BYTES"
        )
    return segments


def _probe_duration_seconds(path: Path) -> float | None:
    cmd = [
        "ffprobe",
        "-v",
        "error",
        "-show_entries",
        "format=duration",
        "-of",
        "default=noprint_wrappers=1:nokey=1",
        str(path),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        return None
    try:
        return float(result.stdout.strip())
    except ValueError:
        return None
