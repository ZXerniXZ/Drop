import asyncio
import shutil
import subprocess
import tempfile
from collections.abc import Callable
from pathlib import Path
from typing import Any

from config import SEGMENT_TARGET_SECONDS
from services.openrouter_service import transcribe_audio_verbose

WHISPER_MAX_BYTES = 24 * 1024 * 1024
SEGMENT_TARGET_BYTES = 20 * 1024 * 1024


async def transcribe_audio_long(
    file_path: str,
    language: str | None = None,
    *,
    on_progress: Callable[[int, int], None] | None = None,
) -> str:
    result = await transcribe_audio_long_verbose(
        file_path, language, on_progress=on_progress
    )
    return result["text"]


async def transcribe_audio_long_verbose(
    file_path: str,
    language: str | None = None,
    *,
    on_progress: Callable[[int, int], None] | None = None,
) -> dict[str, Any]:
    """Trascrive l'audio restituendo testo e timestamp assoluti.

    Gli spezzoni servono sia a rispettare il limite di Whisper sia a dare un
    avanzamento misurabile: i timestamp di ogni spezzone vengono traslati con
    la durata reale degli spezzoni precedenti, non con quella richiesta a
    ffmpeg, che si allinea ai keyframe e quindi varia.
    """
    path = Path(file_path)
    if not path.exists():
        raise FileNotFoundError(f"Audio file not found: {file_path}")

    total_duration = _probe_duration_seconds(path)
    needs_split = path.stat().st_size > WHISPER_MAX_BYTES or (
        total_duration is not None and total_duration > SEGMENT_TARGET_SECONDS
    )

    if not needs_split:
        if on_progress:
            on_progress(1, 1)
        verbose = await transcribe_audio_verbose(file_path, language=language)
        return {
            "text": verbose["text"],
            "duration": verbose.get("duration") or total_duration,
            "segments": _normalize_segments(
                verbose["segments"], verbose["words"], offset=0.0
            ),
        }

    segments_paths = await asyncio.to_thread(_split_audio_file, path, total_duration)
    try:
        texts: list[str] = []
        all_segments: list[dict[str, Any]] = []
        offset = 0.0
        total = len(segments_paths)

        for index, segment_path in enumerate(segments_paths):
            if on_progress:
                on_progress(index + 1, total)

            verbose = await transcribe_audio_verbose(
                str(segment_path), language=language
            )
            text = verbose["text"].strip()
            if text:
                texts.append(text)
            all_segments.extend(
                _normalize_segments(
                    verbose["segments"], verbose["words"], offset=offset
                )
            )

            measured = _probe_duration_seconds(segment_path)
            offset += measured if measured else (verbose.get("duration") or 0.0)

        return {
            "text": "\n\n".join(texts),
            "duration": total_duration or offset,
            "segments": all_segments,
        }
    finally:
        _cleanup_segments(segments_paths)


def _has_speech(text: str) -> bool:
    """Whisper marca silenzi e rumori con segnaposto tipo "-" o "...".

    Quei segmenti non hanno parole associate e nel karaoke sarebbero righe
    morte, quindi vengono scartati.
    """
    return any(char.isalnum() for char in text)


def _normalize_segments(
    segments: list[dict[str, Any]],
    words: list[dict[str, Any]],
    *,
    offset: float,
) -> list[dict[str, Any]]:
    """Uniforma i segmenti Whisper e annida le parole in ciascun segmento."""
    normalized: list[dict[str, Any]] = []

    shifted_words = [
        {
            "w": str(word.get("word", "")),
            "start": _shift(word.get("start"), offset),
            "end": _shift(word.get("end"), offset),
        }
        for word in words
        if _has_speech(str(word.get("word", "")))
    ]

    for segment in segments:
        text = str(segment.get("text", "")).strip()
        if not _has_speech(text):
            continue
        start = _shift(segment.get("start"), offset)
        end = _shift(segment.get("end"), offset)
        normalized.append(
            {
                "start": start,
                "end": end,
                "text": text,
                "words": [
                    word
                    for word in shifted_words
                    if word["start"] >= start - 0.01 and word["start"] < end + 0.01
                ],
            }
        )

    return normalized


def _shift(value: Any, offset: float) -> float:
    try:
        return round(float(value) + offset, 3)
    except (TypeError, ValueError):
        return round(offset, 3)


def _cleanup_segments(segments: list[Path]) -> None:
    for segment in segments:
        segment.unlink(missing_ok=True)
    if segments:
        parent = segments[0].parent
        if parent.name.startswith("drop_segments_"):
            shutil.rmtree(parent, ignore_errors=True)


def _split_audio_file(
    path: Path, total_duration: float | None = None
) -> list[Path]:
    file_size = path.stat().st_size
    duration = total_duration if total_duration is not None else _probe_duration_seconds(path)

    chunk_duration = float(SEGMENT_TARGET_SECONDS)
    if duration and duration > 0:
        # Se il file e' molto denso, il limite di byte e' piu' stringente del tempo.
        byte_based_count = max(
            1, (file_size + SEGMENT_TARGET_BYTES - 1) // SEGMENT_TARGET_BYTES
        )
        chunk_duration = min(chunk_duration, duration / byte_based_count)

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
            "A segment still exceeds Whisper limit; reduce SEGMENT_TARGET_SECONDS"
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
