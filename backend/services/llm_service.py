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
from services.languages import display_name
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

ANALYSIS_KINDS = ("highlights", "speakers", "key_data", "mind_map")

BRIEF_SYSTEM_PROMPT = """You are the assistant for a voice-notes app.
Read the transcript and return ONLY a valid JSON object with this exact schema:

{{
  "title": "short descriptive title (max 60 characters, written in {output_language})",
  "summary": "2 to 4 sentences of plain prose, written in {output_language}"
}}

Rules:
- title and summary MUST be written entirely in {output_language}.
- title: concise, reflects the main content, no date/time.
- summary: a short paragraph a person can read in a few seconds. Plain prose only.
  No markdown, no headings, no bullet lists.
- Do NOT include highlights, key_data, speaker_ids, speaker_view, or formatted_transcript.
- Reply with JSON only, no markdown fences or extra text."""

HIGHLIGHTS_SYSTEM_PROMPT = """You extract next steps from a voice-note transcript.
Return ONLY a valid JSON object:

{{
  "highlights": ["imperative next step"]
}}

Rules:
- 0 to 8 items.
- Each item is one concrete next step, written as an imperative sentence in {output_language}.
- No themes, no summary lines, no quotes.
- If nothing needs doing, return an empty list.
- Reply with JSON only, no markdown fences or extra text."""

SPEAKERS_SYSTEM_PROMPT = """You diarize a voice-note transcript.
Return ONLY a valid JSON object:

{{
  "speaker_ids": [0, 0, 1, 1, 0]
}}

Rules:
- speaker_ids: COMPACT diarization. One integer per numbered segment received
  (same length as the list). 0 = Speaker 0, 1 = Speaker 1, etc.
- Do NOT rewrite segment text.
- If it is a monologue or you cannot tell speakers apart, use all 0.
- Reply with JSON only, no markdown fences or extra text."""

KEY_DATA_SYSTEM_PROMPT = """You extract concrete facts from a voice-note transcript.
Return ONLY a valid JSON object:

{{
  "key_data": {{
    "location": "place or empty string",
    "participants": ["name"],
    "tags": "EXACTLY ONE from the allowed list",
    "deadlines": [{{"when": "when it is due", "what": "what is due"}}],
    "figures": [{{"value": "the number", "what": "what it measures"}}],
    "decisions": ["a commitment that was actually made"]
  }}
}}

Allowed tags (pick exactly ONE): {tag_list}

Rules:
- All prose MUST be written in {output_language}.
- Never invent. Unknown fields are an empty string or an empty list.
- participants: names that were spoken. Do not use Speaker 0 unless no name exists.
- deadlines: only a time tied to something that must happen.
- figures: amounts, counts, or measurements, each with what they refer to.
- decisions: commitments, not topics.
- key_data.tags MUST be one of the allowed tags.
- Reply with JSON only, no markdown fences or extra text."""

MIND_MAP_SYSTEM_PROMPT = """You turn a voice-note transcript into a mind map.
Return ONLY a valid JSON object:

{{
  "mind_map": [
    {{
      "title": "short node title",
      "body": "explanation shown when the title is opened",
      "children": []
    }}
  ]
}}

Rules:
- Write every title and body in {output_language}.
- The map is a tree. The preview shows titles. The body appears only when a title is opened.
- title: one line, max 60 characters, no math, no markdown.
- body: the explanation of that title. Plain prose. Use $...$ for inline math and $$...$$ for a formula on its own line. No other math delimiters.
- children: nested points with the same shape. Depth at most 3. Use [] when a point has no children.
- 3 to 10 top-level points. Follow what was actually said. Do not invent facts.
- A point may have an empty body when it only groups its children.
- Reply with JSON only, no markdown fences or extra text."""

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


def _language_label(output_language: str | None) -> str:
    return display_name(output_language) or "English"


def _tag_pool(available_tags: list[str] | None) -> list[str]:
    tags = [t.strip() for t in (available_tags or DEFAULT_TAGS) if t.strip()]
    return tags or list(DEFAULT_TAGS)


def empty_key_data() -> dict[str, Any]:
    return {
        "location": "",
        "participants": [],
        "tags": "",
        "deadlines": [],
        "figures": [],
        "decisions": [],
    }


def _build_brief_system_prompt(*, output_language: str | None = None) -> str:
    return BRIEF_SYSTEM_PROMPT.format(output_language=_language_label(output_language))


def _build_highlights_system_prompt(*, output_language: str | None = None) -> str:
    return HIGHLIGHTS_SYSTEM_PROMPT.format(
        output_language=_language_label(output_language)
    )


def _build_speakers_system_prompt() -> str:
    return SPEAKERS_SYSTEM_PROMPT


def _build_mind_map_system_prompt(*, output_language: str | None = None) -> str:
    return MIND_MAP_SYSTEM_PROMPT.format(
        output_language=_language_label(output_language)
    )


def _build_key_data_system_prompt(
    available_tags: list[str] | None = None,
    *,
    output_language: str | None = None,
) -> str:
    return KEY_DATA_SYSTEM_PROMPT.format(
        tag_list=" | ".join(_tag_pool(available_tags)),
        output_language=_language_label(output_language),
    )


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


def _as_fact_list(value: Any, lead_key: str, detail_key: str) -> list[dict[str, str]]:
    if not isinstance(value, list):
        return []
    facts: list[dict[str, str]] = []
    for item in value:
        if isinstance(item, str) and item.strip():
            facts.append({lead_key: "", detail_key: item.strip()})
            continue
        if not isinstance(item, dict):
            continue
        lead = str(item.get(lead_key) or "").strip()
        detail = str(item.get(detail_key) or item.get("what") or "").strip()
        if not lead and not detail:
            continue
        facts.append({lead_key: lead, detail_key: detail})
    return facts[:8]


def _normalize_key_data(
    value: Any, allowed_tags: list[str] | None = None
) -> dict[str, Any]:
    pool = _tag_pool(allowed_tags)
    if not isinstance(value, dict):
        data = empty_key_data()
        data["tags"] = pool[0]
        return data

    participants = value.get("participants", [])
    if not isinstance(participants, list):
        participants = []

    tags = str(value.get("tags", "")).strip()
    matched = next((t for t in pool if t.lower() == tags.lower()), pool[0])

    return {
        "location": str(value.get("location", "")).strip(),
        "participants": [str(p).strip() for p in participants if str(p).strip()],
        "tags": matched,
        "deadlines": _as_fact_list(value.get("deadlines"), "when", "what"),
        "figures": _as_fact_list(value.get("figures"), "value", "what"),
        "decisions": _as_string_list(value.get("decisions"))[:8],
    }


_MAX_MIND_NODES = 40
_MAX_MIND_DEPTH = 3


def _normalize_mind_map(value: Any) -> list[dict[str, Any]]:
    count = 0

    def walk(raw: Any, depth: int) -> list[dict[str, Any]]:
        nonlocal count
        if not isinstance(raw, list) or depth > _MAX_MIND_DEPTH:
            return []
        nodes: list[dict[str, Any]] = []
        for item in raw:
            if count >= _MAX_MIND_NODES:
                break
            if not isinstance(item, dict):
                continue
            title = str(item.get("title") or "").strip()
            body = str(
                item.get("body") or item.get("explanation") or item.get("detail") or ""
            ).strip()
            if not title and not body:
                continue
            if not title:
                title = body.split("\n", 1)[0][:60]
            count += 1
            children = (
                walk(item.get("children") or item.get("nodes"), depth + 1)
                if depth < _MAX_MIND_DEPTH
                else []
            )
            nodes.append(
                {
                    "title": title[:80],
                    "body": body[:2000],
                    "children": children,
                }
            )
        return nodes

    if isinstance(value, dict):
        value = value.get("mind_map") or value.get("nodes")
    return walk(value, 1)


def _with_custom_prompt(prompt: str, custom_prompt: str | None) -> str:
    if custom_prompt and custom_prompt.strip():
        return f"{prompt}\n\nIstruzioni aggiuntive dell'utente:\n{custom_prompt.strip()}"
    return prompt


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


async def _complete_json(
    *,
    system: str,
    user: str,
    model: str | None,
    api_key: str | None,
) -> dict[str, Any]:
    resolved_key = (api_key or "").strip() or OPENROUTER_API_KEY
    if not resolved_key:
        raise ValueError("OPENROUTER_API_KEY is not configured")

    headers = {
        "Authorization": f"Bearer {resolved_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": APP_REFERER,
        "X-Title": APP_TITLE,
    }
    payload = {
        "model": resolve_llm_model(model),
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
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
    return _load_first_json_object(content)


async def process_transcript(
    transcript: str,
    *,
    model: str | None = None,
    custom_prompt: str | None = None,
    language: str | None = None,
    available_tags: list[str] | None = None,
    segments: list[dict[str, Any]] | None = None,
    api_key: str | None = None,
) -> dict[str, Any]:
    del available_tags, segments
    label = _language_label(language)
    user_prompt = _with_custom_prompt(
        f"Write the title and the summary in {label}.\n\n"
        "Trascrizione:\n\n"
        f"{_truncate_transcript(transcript)}",
        custom_prompt,
    )
    data = await _complete_json(
        system=_build_brief_system_prompt(output_language=language),
        user=user_prompt,
        model=model,
        api_key=api_key,
    )
    title = str(data.get("title", "")).strip() or "Voice note"
    summary = str(data.get("summary", "")).strip()
    if not summary:
        raise ValueError("LLM response missing summary")
    parsed = {"title": title[:80], "summary": summary}
    return {
        "title": parsed["title"],
        "summary": parsed["summary"],
        "highlights": [],
        "key_data": empty_key_data(),
        "speaker_view": [],
        "formatted_transcript": transcript,
        "mind_map": [],
        "analysis_state": {},
    }


async def process_optional_analysis(
    kind: str,
    transcript: str,
    *,
    model: str | None = None,
    custom_prompt: str | None = None,
    language: str | None = None,
    available_tags: list[str] | None = None,
    segments: list[dict[str, Any]] | None = None,
    api_key: str | None = None,
) -> dict[str, Any]:
    if kind not in ANALYSIS_KINDS:
        raise ValueError(f"Unknown analysis kind: {kind}")

    clipped = _truncate_transcript(transcript)
    label = _language_label(language)

    if kind == "highlights":
        data = await _complete_json(
            system=_build_highlights_system_prompt(output_language=language),
            user=_with_custom_prompt(
                f"Write every highlight in {label}.\n\nTrascrizione:\n\n{clipped}",
                custom_prompt,
            ),
            model=model,
            api_key=api_key,
        )
        return {"highlights": _as_string_list(data.get("highlights"))[:8]}

    if kind == "speakers":
        if not segments:
            view, formatted = build_from_raw_transcript(transcript)
            return {
                "speaker_view": view,
                "formatted_transcript": formatted or transcript,
            }
        numbered = format_segments_for_diarization(segments)
        data = await _complete_json(
            system=_build_speakers_system_prompt(),
            user=_with_custom_prompt(
                f"Ci sono {len(segments)} segmenti Whisper. Restituisci "
                f"speaker_ids con esattamente {len(segments)} interi (0-based). "
                "Non riscrivere il testo dei segmenti.\n\n"
                f"Segmenti numerati:\n\n{numbered}",
                custom_prompt,
            ),
            model=model,
            api_key=api_key,
        )
        speaker_view, formatted = _assemble_speaker_fields(
            transcript,
            segments=segments,
            speaker_ids=data.get("speaker_ids"),
        )
        return {
            "speaker_view": speaker_view,
            "formatted_transcript": formatted or transcript,
        }

    if kind == "mind_map":
        data = await _complete_json(
            system=_build_mind_map_system_prompt(output_language=language),
            user=_with_custom_prompt(
                f"Write every title and body in {label}.\n\nTrascrizione:\n\n{clipped}",
                custom_prompt,
            ),
            model=model,
            api_key=api_key,
        )
        return {"mind_map": _normalize_mind_map(data.get("mind_map"))}

    data = await _complete_json(
        system=_build_key_data_system_prompt(
            available_tags, output_language=language
        ),
        user=_with_custom_prompt(
            f"Write every text field in {label}.\n\nTrascrizione:\n\n{clipped}",
            custom_prompt,
        ),
        model=model,
        api_key=api_key,
    )
    return {"key_data": _normalize_key_data(data.get("key_data"), available_tags)}
