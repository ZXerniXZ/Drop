import asyncio
import shutil
import subprocess
import tempfile
from collections.abc import Callable
from pathlib import Path
from typing import Any

from config import SEGMENT_TARGET_SECONDS
from services.openrouter_service import (
    MAX_TRANSCRIPTION_FILE_BYTES,
    transcribe_audio_verbose,
)

# Un solo encode AAC a 16 kHz / 64 kbps: Whisper non usa la banda in più e
# lo spezzone resta sotto il tetto OpenRouter. Il file originale non si tocca.
SPEECH_SAMPLE_RATE = "16000"
SPEECH_BITRATE = "64k"
HIGHPASS_HZ = 80
# -16 LUFS in un passaggio: niente seconda decodifica solo per misurare.
LOUDNORM = "loudnorm=I=-16:TP=-1.5:LRA=11"
# mix < 1 lascia passare parte del segnale originale, così le fricative
# non vengono cancellate insieme al rumore.
DENOISE_FILTER = "arnndn=mix=0.6"
DENOISE_FALLBACK = "afftdn=nr=8:nf=-50"


async def transcribe_audio_long(
    file_path: str,
    language: str | None = None,
    *,
    on_progress: Callable[[int, int], None] | None = None,
    api_key: str | None = None,
) -> str:
    result = await transcribe_audio_long_verbose(
        file_path, language, on_progress=on_progress, api_key=api_key
    )
    return result["text"]


def speech_audio_filter(*, denoise: bool, denoise_stage: str | None = None) -> str:
    """Passa-alto, volume normalizzato e, se richiesto, riduzione del rumore."""
    stages = [f"highpass=f={HIGHPASS_HZ}"]
    if denoise:
        stages.append(denoise_stage or DENOISE_FILTER)
    stages.append(LOUDNORM)
    return ",".join(stages)


def speech_filter_attempts(*, denoise: bool) -> list[str]:
    """Prima RNNoise, poi il denoise FFT se quel filtro non c'è nel ffmpeg."""
    attempts = [speech_audio_filter(denoise=denoise)]
    if denoise:
        attempts.append(
            speech_audio_filter(denoise=True, denoise_stage=DENOISE_FALLBACK)
        )
    return attempts


def denoise_filter_unsupported(stderr: str) -> bool:
    text = stderr.lower()
    return "arnndn" in text or "no such filter" in text


async def transcribe_audio_long_verbose(
    file_path: str,
    language: str | None = None,
    *,
    on_progress: Callable[[int, int], None] | None = None,
    api_key: str | None = None,
    denoise: bool = False,
) -> dict[str, Any]:
    """Trascrive l'audio restituendo testo e timestamp assoluti.

    L'audio inviato a Whisper è sempre una ricodifica unica: passa-alto,
    loudness e AAC 16 kHz. Gli spezzoni, se servono, escono dallo stesso
    comando ffmpeg, così non c'è una seconda compressione.
    """
    path = Path(file_path)
    if not path.exists():
        raise FileNotFoundError(f"Audio file not found: {file_path}")

    total_duration = probe_duration_seconds(path)
    segments_paths = await asyncio.to_thread(
        prepare_speech_segments, path, denoise=denoise
    )
    try:
        texts: list[str] = []
        all_segments: list[dict[str, Any]] = []
        offset = 0.0
        total = len(segments_paths)

        for index, segment_path in enumerate(segments_paths):
            if on_progress:
                on_progress(index + 1, total)

            verbose = await transcribe_audio_verbose(
                str(segment_path), language=language, api_key=api_key
            )
            text = verbose["text"].strip()
            if text:
                texts.append(text)
            all_segments.extend(
                _normalize_segments(
                    verbose["segments"], verbose["words"], offset=offset
                )
            )

            measured = probe_duration_seconds(segment_path)
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
        if parent.name.startswith(("drop_segments_", "drop_speech_")):
            shutil.rmtree(parent, ignore_errors=True)


def prepare_speech_segments(path: Path, *, denoise: bool = False) -> list[Path]:
    """Prepara l'audio per Whisper senza modificare il file originale.

    Un solo encode AAC. Se la registrazione supera SEGMENT_TARGET_SECONDS,
    gli spezzoni nascono in quel comando: niente seconda compressione.
    """
    if not path.is_file():
        raise FileNotFoundError(f"Audio file not found: {path}")

    tmp_dir = Path(tempfile.mkdtemp(prefix="drop_speech_"))
    try:
        return _encode_speech_segments(path, tmp_dir, denoise=denoise)
    except Exception:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        raise


def _encode_speech_segments(
    path: Path, tmp_dir: Path, *, denoise: bool
) -> list[Path]:
    filters = speech_filter_attempts(denoise=denoise)

    last_error = ""
    for index, audio_filter in enumerate(filters):
        _clear_encoded(tmp_dir)
        result = _run_speech_ffmpeg(path, tmp_dir, audio_filter)
        segments = sorted(tmp_dir.glob("segment_*.m4a"))
        if result.returncode == 0 and segments:
            oversized = [
                segment
                for segment in segments
                if segment.stat().st_size > MAX_TRANSCRIPTION_FILE_BYTES
            ]
            if oversized:
                raise RuntimeError(
                    "A segment still exceeds OpenRouter limit; "
                    "reduce SEGMENT_TARGET_SECONDS"
                )
            return segments

        last_error = (result.stderr or result.stdout or "").strip()
        if index == 0 and denoise and denoise_filter_unsupported(last_error):
            continue
        break

    raise RuntimeError(f"ffmpeg speech prepare failed: {last_error}")


def _run_speech_ffmpeg(
    source: Path, tmp_dir: Path, audio_filter: str
) -> subprocess.CompletedProcess[str]:
    pattern = tmp_dir / "segment_%03d.m4a"
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        str(source),
        "-af",
        audio_filter,
        "-ac",
        "1",
        "-ar",
        SPEECH_SAMPLE_RATE,
        "-c:a",
        "aac",
        "-b:a",
        SPEECH_BITRATE,
        "-f",
        "segment",
        "-segment_time",
        str(float(SEGMENT_TARGET_SECONDS)),
        "-reset_timestamps",
        "1",
        str(pattern),
    ]
    return subprocess.run(cmd, capture_output=True, text=True)


def _clear_encoded(tmp_dir: Path) -> None:
    for segment in tmp_dir.glob("segment_*.m4a"):
        segment.unlink(missing_ok=True)


def probe_duration_seconds(path: Path) -> float | None:
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
