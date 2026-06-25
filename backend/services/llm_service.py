import json
import re
from typing import Any

import httpx

from config import OPENROUTER_API_KEY, OPENROUTER_LLM_MODEL

OPENROUTER_CHAT_URL = "https://openrouter.ai/api/v1/chat/completions"
LLM_TIMEOUT_SECONDS = 180.0
APP_REFERER = "https://github.com/ZXerniXZ/Drop"
APP_TITLE = "Drop"

MODEL_ALIASES: dict[str, str] = {
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

SYSTEM_PROMPT = """Sei l'assistente di un'app di note vocali stile Plaud Note.
Analizza la trascrizione grezza e restituisci SOLO un oggetto JSON valido con questo schema esatto:

{
  "summary": "stringa Markdown con sezioni ## Overview, ## Key Decisions e altre sezioni utili",
  "highlights": ["action item o punto chiave 1", "punto 2"],
  "key_data": {
    "location": "luogo dedotto o stringa vuota",
    "participants": ["nome o Speaker 0", "Speaker 1"],
    "tags": "Meeting | Lezione | Diario"
  },
  "speaker_view": [
    {"speaker": "Speaker 0", "text": "testo pronunciato", "time": "00:00"}
  ],
  "formatted_transcript": "trascrizione formattata con etichette speaker per lettura lineare"
}

Regole:
- highlights: 2-8 elementi concreti e actionable quando possibile.
- speaker_view: separa logicamente il dialogo per speaker; se monologo usa Speaker 0.
- key_data.tags: scegli UNA tra Meeting, Lezione, Diario in base al contenuto.
- Rispondi SOLO con JSON, senza markdown fence o testo extra."""


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
        text = re.sub(r"\s*```$", "", text.strip())
    return text


def _as_string_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [str(item).strip() for item in value if str(item).strip()]


def _normalize_speaker_view(value: Any) -> list[dict[str, str]]:
    if not isinstance(value, list):
        return []
    blocks: list[dict[str, str]] = []
    for item in value:
        if not isinstance(item, dict):
            continue
        speaker = str(item.get("speaker", "Speaker 0")).strip() or "Speaker 0"
        text = str(item.get("text", "")).strip()
        if not text:
            continue
        block = {"speaker": speaker, "text": text}
        time_value = item.get("time")
        if time_value:
            block["time"] = str(time_value).strip()
        blocks.append(block)
    return blocks


def _normalize_key_data(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        return {"location": "", "participants": [], "tags": "Diario"}

    participants = value.get("participants", [])
    if not isinstance(participants, list):
        participants = []

    tags = str(value.get("tags", "Diario")).strip() or "Diario"
    if tags not in {"Meeting", "Lezione", "Diario"}:
        tags = "Diario"

    return {
        "location": str(value.get("location", "")).strip(),
        "participants": [str(p).strip() for p in participants if str(p).strip()],
        "tags": tags,
    }


def _speaker_view_to_formatted(speaker_view: list[dict[str, str]]) -> str:
    if not speaker_view:
        return ""
    parts: list[str] = []
    for block in speaker_view:
        label = block["speaker"]
        time_suffix = f" [{block['time']}]" if block.get("time") else ""
        parts.append(f"{label}{time_suffix}: {block['text']}")
    return "\n\n".join(parts)


def _parse_llm_json(content: str) -> dict[str, Any]:
    data = json.loads(_strip_json_fence(content))

    summary = str(data.get("summary", "")).strip()
    highlights = _as_string_list(data.get("highlights"))
    key_data = _normalize_key_data(data.get("key_data"))
    speaker_view = _normalize_speaker_view(data.get("speaker_view"))

    formatted = str(data.get("formatted_transcript", "")).strip()
    if not formatted:
        formatted = _speaker_view_to_formatted(speaker_view)

    if not summary:
        raise ValueError("LLM response missing summary")

    return {
        "summary": summary,
        "highlights": highlights,
        "key_data": key_data,
        "speaker_view": speaker_view,
        "formatted_transcript": formatted or summary,
    }


def _build_user_prompt(transcript: str, custom_prompt: str | None) -> str:
    parts = [f"Trascrizione grezza:\n\n{transcript}"]
    if custom_prompt and custom_prompt.strip():
        parts.append(
            f"\n\nIstruzioni aggiuntive dell'utente:\n{custom_prompt.strip()}"
        )
    return "".join(parts)


async def process_transcript(
    transcript: str,
    *,
    model: str | None = None,
    custom_prompt: str | None = None,
    language: str | None = None,
) -> dict[str, Any]:
    if not OPENROUTER_API_KEY:
        raise ValueError("OPENROUTER_API_KEY is not configured")

    resolved_model = resolve_llm_model(model)
    user_prompt = _build_user_prompt(transcript, custom_prompt)

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
            {"role": "system", "content": SYSTEM_PROMPT},
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

    return _parse_llm_json(content)
