"""Monta speaker_view e formatted_transcript dai segmenti Whisper.

L'LLM fa solo diarizzazione compatta (chi parla in ciascun segmento); il testo
resta quello verbatim di Whisper, cosi' non si riassume e non si riscrive
tutta la trascrizione in output.
"""

from __future__ import annotations

from typing import Any


def format_mmss(seconds: float) -> str:
    total = max(0, int(seconds))
    return f"{total // 60:02d}:{total % 60:02d}"


def normalize_speaker_ids(value: Any, segment_count: int) -> list[int]:
    """Allinea speaker_ids alla lunghezza dei segmenti; fallback tutto Speaker 0."""
    if segment_count <= 0:
        return []
    if not isinstance(value, list):
        return [0] * segment_count

    ids: list[int] = []
    for item in value:
        try:
            ids.append(max(0, int(item)))
        except (TypeError, ValueError):
            ids.append(0)

    if len(ids) < segment_count:
        ids.extend([ids[-1] if ids else 0] * (segment_count - len(ids)))
    elif len(ids) > segment_count:
        ids = ids[:segment_count]
    return ids


def build_speaker_view(
    segments: list[dict[str, Any]],
    speaker_ids: list[int] | None = None,
) -> list[dict[str, str]]:
    """Unisce segmenti consecutivi dello stesso speaker in blocchi verbatim."""
    if not segments:
        return []

    ids = normalize_speaker_ids(speaker_ids, len(segments))
    blocks: list[dict[str, str]] = []

    current_speaker = ids[0]
    current_start = float(segments[0].get("start") or 0.0)
    texts: list[str] = []

    def flush() -> None:
        nonlocal texts
        joined = " ".join(t for t in texts if t).strip()
        texts = []
        if not joined:
            return
        blocks.append(
            {
                "speaker": f"Speaker {current_speaker}",
                "text": joined,
                "time": format_mmss(current_start),
            }
        )

    for index, segment in enumerate(segments):
        text = str(segment.get("text", "")).strip()
        speaker = ids[index]
        start = float(segment.get("start") or 0.0)

        if speaker != current_speaker and texts:
            flush()
            current_speaker = speaker
            current_start = start

        if not texts:
            current_speaker = speaker
            current_start = start
        if text:
            texts.append(text)

    flush()
    return blocks


def speaker_view_to_formatted(speaker_view: list[dict[str, str]]) -> str:
    if not speaker_view:
        return ""
    parts: list[str] = []
    for block in speaker_view:
        time_value = block.get("time")
        time_suffix = f" - {time_value}" if time_value else ""
        parts.append(f"[{block['speaker']}{time_suffix}]: {block['text']}")
    return "\n".join(parts)


def build_from_raw_transcript(transcript: str) -> tuple[list[dict[str, str]], str]:
    """Fallback senza segmenti: un solo blocco con tutta la trascrizione grezza."""
    text = transcript.strip()
    if not text:
        return [], ""
    view = [{"speaker": "Speaker 0", "text": text, "time": "00:00"}]
    return view, speaker_view_to_formatted(view)


def format_segments_for_diarization(
    segments: list[dict[str, Any]], *, max_chars_per_segment: int = 280
) -> str:
    """Elenco numerato leggero da passare all'LLM per la sola diarizzazione."""
    lines: list[str] = []
    for index, segment in enumerate(segments):
        start = format_mmss(float(segment.get("start") or 0.0))
        text = str(segment.get("text", "")).strip().replace("\n", " ")
        if len(text) > max_chars_per_segment:
            text = text[: max_chars_per_segment - 1] + "…"
        lines.append(f"[{index}] [{start}] {text}")
    return "\n".join(lines)
