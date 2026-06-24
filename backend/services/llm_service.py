import json
import re

import httpx

from config import OPENROUTER_API_KEY, OPENROUTER_LLM_MODEL

OPENROUTER_CHAT_URL = "https://openrouter.ai/api/v1/chat/completions"
LLM_TIMEOUT_SECONDS = 120.0
APP_REFERER = "https://github.com/ZXerniXZ/Drop"
APP_TITLE = "Drop"

SYSTEM_PROMPT = """Sei l'assistente di un dispositivo di registrazione stile Plaud Note. Prendi questa trascrizione grezza e restituisci un JSON con due chiavi:
1. "formatted_transcript": il testo diviso in paragrafi logici inserendo dei tag "Interlocutore A:" e "Interlocutore B:" basandoti sul contesto della conversazione.
2. "summary": un riassunto esecutivo strutturato in Markdown (Titolo, Punti Chiave, Cose da fare).

Rispondi SOLO con JSON valido, senza testo aggiuntivo."""


def _parse_llm_json(content: str) -> dict:
    text = content.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text.strip())

    data = json.loads(text)
    formatted = data.get("formatted_transcript")
    summary = data.get("summary")

    if not formatted or not summary:
        raise ValueError("LLM response missing formatted_transcript or summary")

    return {
        "formatted_transcript": formatted,
        "summary": summary,
    }


async def process_transcript(transcript: str) -> dict:
    if not OPENROUTER_API_KEY:
        raise ValueError("OPENROUTER_API_KEY is not configured")

    headers = {
        "Authorization": f"Bearer {OPENROUTER_API_KEY}",
        "Content-Type": "application/json",
        "HTTP-Referer": APP_REFERER,
        "X-Title": APP_TITLE,
    }

    payload = {
        "model": OPENROUTER_LLM_MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": transcript},
        ],
        "response_format": {"type": "json_object"},
    }

    async with httpx.AsyncClient(timeout=LLM_TIMEOUT_SECONDS) as client:
        response = await client.post(
            OPENROUTER_CHAT_URL,
            json=payload,
            headers=headers,
        )
        response.raise_for_status()
        data = response.json()

    try:
        content = data["choices"][0]["message"]["content"]
    except (KeyError, IndexError) as exc:
        raise ValueError("Unexpected OpenRouter chat response format") from exc

    return _parse_llm_json(content)
