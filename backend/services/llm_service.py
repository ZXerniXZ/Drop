import json
import re
from typing import Any

import httpx

from config import (
    LLM_TIMEOUT_SECONDS,
    MAX_TRANSCRIPT_CHARS,
    OPENROUTER_API_KEY,
    OPENROUTER_LLM_MODEL,
)
from services.speaker_assembly import (
    build_from_raw_transcript,
    build_speaker_view,
    format_segments_for_diarization,
    speaker_view_to_formatted,
)

OPENROUTER_CHAT_URL = "https://openrouter.ai/api/v1/chat/completions"
APP_REFERER = "https://github.com/ZXerniXZ/Drop"
APP_TITLE = "Drop"

MODEL_ALIASES: dict[str, str] = {
    "gemini_36_flash": "google/gemini-3.6-flash",
    "gemini36flash": "google/gemini-3.6-flash",
    "gemini 3.6 flash": "google/gemini-3.6-flash",
    "google/gemini-3.6-flash": "google/gemini-3.6-flash",
    "gemini_35_flash": "google/gemini-3.5-flash",
    "gemini35flash": "google/gemini-3.5-flash",
    "gemini 3.5 flash": "google/gemini-3.5-flash",
    "google/gemini-3.5-flash": "google/gemini-3.5-flash",
    "gemini_flash": "google/gemini-2.5-flash",
    "geminiflash": "google/gemini-2.5-flash",
    "gemini 2.5 flash": "google/gemini-2.5-flash",
    "google/gemini-2.5-flash": "google/gemini-2.5-flash",
    "gemini_pro": "google/gemini-2.5-pro",
    "geminipro": "google/gemini-2.5-pro",
    "gemini 2.5 pro": "google/gemini-2.5-pro",
    "google/gemini-2.5-pro": "google/gemini-2.5-pro",
}

SYSTEM_PROMPT_TEMPLATE = """Sei l'assistente di un'app di note vocali stile Plaud Note.
Analizza la trascrizione e restituisci SOLO un oggetto JSON valido con questo schema esatto:

{{
  "title": "titolo breve e descrittivo della nota (max 60 caratteri, in italiano)",
  "summary": "stringa Markdown con sezioni ## Overview, ## Key Decisions e altre sezioni utili",
  "highlights": ["action item o punto chiave 1", "punto 2"],
  "key_data": {{
    "location": "luogo dedotto o stringa vuota",
    "participants": ["nome o Speaker 0", "Speaker 1"],
    "tags": "UNO dalla lista consentita"
  }},
  "speaker_ids": [0, 0, 1, 1, 0]
}}

Tag consentiti (scegline esattamente UNO per key_data.tags): {tag_list}

Regole:
- title: sintetico, riflette il contenuto principale, senza data/ora.
- highlights: 2-8 elementi concreti e actionable quando possibile.
- summary: puoi riassumere liberamente.
- speaker_ids: diarizzazione COMPATTA. Un intero per ogni segmento numerato ricevuto
  (stessa lunghezza dell'elenco). 0 = Speaker 0, 1 = Speaker 1, ecc.
  NON riscrivere il testo dei segmenti: il server lo monta da Whisper.
  Se monologo o non sai distinguere, usa tutti 0.
- key_data.tags: DEVE essere uno dei tag consentiti sopra.
- NON includere speaker_view ne' formatted_transcript.
- Rispondi SOLO con JSON, senza markdown fence o testo extra."""

DEFAULT_TAGS = [
    "Meeting",
    "Lezione",
    "Diario",
    "Lavoro",
    "Intervista",
    "Brainstorm",
    "Memo",
    "Chiamata",
]


def _build_system_prompt(available_tags: list[str] | None = None) -> str:
    tags = [t.strip() for t in (available_tags or DEFAULT_TAGS) if t.strip()]
    if not tags:
        tags = DEFAULT_TAGS
    return SYSTEM_PROMPT_TEMPLATE.format(tag_list=" | ".join(tags))


def resolve_llm_model(ai_model: str | None) -> str:
    if not ai_model:
        return OPENROUTER_LLM_MODEL
    stripped = ai_model.strip()
    if "/" in stripped:
        return stripped
    normalized = stripped.lower().replace("-", "_").replace(" ", "_")
    label_normalized = stripped.lower()
    return MODEL_ALIASES.get(normalized) or MODEL_ALIASES.get(
        label_normalized, OPENROUTER_LLM_MODEL
    )


def _strip_json_fence(content: str) -> str:
    text = content.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```[\s\S]*$", "", text.strip())
    return text.strip()


def _load_first_json_object(content: str) -> dict[str, Any]:
    text = _strip_json_fence(content)
    start = text.find("{")
    if start == -1:
        raise ValueError("LLM response missing JSON object")

    decoder = json.JSONDecoder()
    data, _end = decoder.raw_decode(text, start)
    if not isinstance(data, dict):
        raise ValueError("LLM response JSON root must be an object")
    return data


def _as_string_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [str(item).strip() for item in value if str(item).strip()]


def _normalize_key_data(
    value: Any, allowed_tags: list[str] | None = None
) -> dict[str, Any]:
    if not isinstance(value, dict):
        default_tag = (allowed_tags or DEFAULT_TAGS)[0]
        return {"location": "", "participants": [], "tags": default_tag}

    participants = value.get("participants", [])
    if not isinstance(participants, list):
        participants = []

    pool = [t.strip() for t in (allowed_tags or DEFAULT_TAGS) if t.strip()]
    if not pool:
        pool = DEFAULT_TAGS

    tags = str(value.get("tags", pool[0])).strip() or pool[0]
    matched = next((t for t in pool if t.lower() == tags.lower()), pool[0])

    return {
        "location": str(value.get("location", "")).strip(),
        "participants": [str(p).strip() for p in participants if str(p).strip()],
        "tags": matched,
    }


def _parse_llm_json(
    content: str, allowed_tags: list[str] | None = None
) -> dict[str, Any]:
    data = _load_first_json_object(content)

    title = str(data.get("title", "")).strip()
    summary = str(data.get("summary", "")).strip()
    highlights = _as_string_list(data.get("highlights"))
    key_data = _normalize_key_data(data.get("key_data"), allowed_tags)

    if not summary:
        raise ValueError("LLM response missing summary")

    if not title:
        title = "Nota vocale"

    return {
        "title": title[:80],
        "summary": summary,
        "highlights": highlights,
        "key_data": key_data,
        "speaker_ids": data.get("speaker_ids"),
    }


def _build_user_prompt(
    transcript: str,
    custom_prompt: str | None,
    *,
    segments: list[dict[str, Any]] | None = None,
) -> str:
    parts = [
        "Trascrizione grezza (per titolo, summary, highlights):\n\n",
        transcript,
    ]
    if segments:
        numbered = format_segments_for_diarization(segments)
        parts.append(
            f"\n\nCi sono {len(segments)} segmenti Whisper. Restituisci "
            f"speaker_ids con esattamente {len(segments)} interi (0-based). "
            "Non riscrivere il testo dei segmenti.\n\n"
            f"Segmenti numerati:\n\n{numbered}"
        )

    if custom_prompt and custom_prompt.strip():
        parts.append(
            f"\n\nIstruzioni aggiuntive dell'utente:\n{custom_prompt.strip()}"
        )
    return "".join(parts)


def _truncate_transcript(text: str) -> str:
    if len(text) <= MAX_TRANSCRIPT_CHARS:
        return text
    return text[:MAX_TRANSCRIPT_CHARS] + "\n\n[... trascrizione troncata per analisi LLM ...]"


def _assemble_speaker_fields(
    transcript: str,
    *,
    segments: list[dict[str, Any]] | None,
    speaker_ids: Any,
) -> tuple[list[dict[str, str]], str]:
    if segments:
        speaker_view = build_speaker_view(segments, speaker_ids)
        if speaker_view:
            return speaker_view, speaker_view_to_formatted(speaker_view)
    return build_from_raw_transcript(transcript)


async def process_transcript(
    transcript: str,
    *,
    model: str | None = None,
    custom_prompt: str | None = None,
    language: str | None = None,
    available_tags: list[str] | None = None,
    segments: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    if not OPENROUTER_API_KEY:
        raise ValueError("OPENROUTER_API_KEY is not configured")

    resolved_model = resolve_llm_model(model)
    user_prompt = _build_user_prompt(
        _truncate_transcript(transcript),
        custom_prompt,
        segments=segments,
    )
    tags_pool = [t.strip() for t in (available_tags or DEFAULT_TAGS) if t.strip()]

    if language and language.strip().lower() not in {"automatic", "automatico", ""}:
        user_prompt = (
            f"Lingua richiesta per l'output: {language.strip()}\n\n{user_prompt}"
        )

    headers = {
        "Authorization": f"Bearer {OPENROUTER_API_KEY}",
        "Content-Type": "application/json",
        "HTTP-Referer": APP_REFERER,
        "X-Title": APP_TITLE,
    }

    payload = {
        "model": resolved_model,
        "messages": [
            {"role": "system", "content": _build_system_prompt(tags_pool)},
            {"role": "user", "content": user_prompt},
        ],
        "response_format": {"type": "json_object"},
    }

    async with httpx.AsyncClient(timeout=LLM_TIMEOUT_SECONDS) as client:
        response = await client.post(
            OPENROUTER_CHAT_URL,
            json=payload,
            headers=headers,
        )
        if response.is_error:
            raise ValueError(
                f"OpenRouter LLM error {response.status_code}: {response.text}"
            )
        data = response.json()

    try:
        content = data["choices"][0]["message"]["content"]
    except (KeyError, IndexError) as exc:
        raise ValueError("Unexpected OpenRouter chat response format") from exc

    parsed = _parse_llm_json(content, tags_pool)
    speaker_view, formatted = _assemble_speaker_fields(
        transcript,
        segments=segments,
        speaker_ids=parsed.pop("speaker_ids", None),
    )
    parsed["speaker_view"] = speaker_view
    parsed["formatted_transcript"] = formatted or transcript
    return parsed
