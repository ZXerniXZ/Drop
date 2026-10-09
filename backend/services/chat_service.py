import json
from collections.abc import AsyncIterator
from typing import Any, Literal

import httpx
from pydantic import BaseModel, Field

from config import OPENROUTER_API_KEY
from services.languages import display_name
from services.llm_service import (
    APP_REFERER,
    APP_TITLE,
    OPENROUTER_CHAT_URL,
    resolve_llm_model,
)

CHAT_TIMEOUT_SECONDS = 120.0
MAX_HISTORY_MESSAGES = 10
MAX_TRANSCRIPT_CHARS = 12_000
HEAD_TAIL_CHARS = 4_000

NOTE_CHAT_SYSTEM_PROMPT = """You are Drop, an AI assistant for a single voice note.
Reply ONLY from the provided note context. If the information is not in the context, say so clearly.
Reply in {output_language}, concisely and helpfully. Bullet lists or light markdown are fine.
Use $...$ for inline math and a line with $$...$$ for a display formula. Do not use \\( \\), \\[ \\], or bare LaTeX.
When the answer includes source code, a command, or configuration, put it in a fenced markdown block with a language tag. Keep the original indentation and line breaks. Do not wrap the whole reply in one fence, and do not place code inside math delimiters.
When a graph makes the explanation clearer — a function, a geometric relation, or numbers stated in the note — add at most two fenced blocks tagged drop-visual. Plot those cases instead of only describing the shape. The fence body is one JSON object, one of:
- {{"kind":"plot2d","title":"optional","expressions":["x^2"],"x":[-2,2]}}
- {{"kind":"surface3d","title":"optional","expression":"x^2+y^2","x":[-2,2],"y":[-2,2]}}
- {{"kind":"curve3d","title":"optional","x":"cos(t)","y":"sin(t)","z":"t/5","t":[0,12.56]}}
- {{"kind":"chart","title":"optional","type":"bar","labels":["A","B"],"series":[{{"name":"value","values":[1,2]}}]}}
Expressions use math.js syntax: x, y, or t, with + - * / ^, sqrt, sin, cos, tan, exp, log, abs, pi. Write only the right-hand side ("x^2", not "y = x^2"). Use plain ASCII, no LaTeX. Replace every constant with the number from the note; if no number was said, use a simple value like 1 so the shape still shows. No assignments, no imports.
Ranges are two finite numbers, low then high. chart type is "bar" or "line", at most 50 points, and only for quantities that were actually stated. Do not invent data."""


class ChatHistoryMessage(BaseModel):
    role: Literal["user", "assistant"]
    content: str


class NoteContext(BaseModel):
    title: str = ""
    tag: str = ""
    date_time: str = ""
    raw_transcription: str = ""
    formatted_transcription: str = ""
    summary: str = ""
    highlights: list[str] = Field(default_factory=list)
    key_data: dict[str, Any] = Field(default_factory=dict)
    speaker_view: list[dict[str, Any]] = Field(default_factory=list)
    mind_map: list[dict[str, Any]] = Field(default_factory=list)


class NoteChatRequest(BaseModel):
    message: str
    note_id: str
    history: list[ChatHistoryMessage] = Field(default_factory=list)
    ai_model: str | None = None
    output_language: str | None = None
    note_context: NoteContext


def _truncate_transcript(text: str) -> str:
    if len(text) <= MAX_TRANSCRIPT_CHARS:
        return text
    head = text[:HEAD_TAIL_CHARS]
    tail = text[-HEAD_TAIL_CHARS:]
    omitted = len(text) - HEAD_TAIL_CHARS * 2
    return f"{head}\n\n[... {omitted} caratteri omessi ...]\n\n{tail}"


def _mind_map_outline(nodes: list[dict[str, Any]], depth: int = 0) -> str:
    lines: list[str] = []
    indent = "  " * depth
    for node in nodes:
        if not isinstance(node, dict):
            continue
        title = str(node.get("title") or "").strip()
        body = str(node.get("body") or "").strip()
        if title:
            lines.append(f"{indent}- {title}")
        if body:
            lines.append(f"{indent}  {body}")
        visuals = node.get("visuals")
        if isinstance(visuals, list) and visuals:
            kinds = [
                str(item.get("kind"))
                for item in visuals
                if isinstance(item, dict) and item.get("kind")
            ]
            if kinds:
                lines.append(f"{indent}  [grafici: {', '.join(kinds)}]")
        children = node.get("children")
        if isinstance(children, list) and children and depth < 4:
            nested = _mind_map_outline(children, depth + 1)
            if nested:
                lines.append(nested)
    return "\n".join(lines)


def _build_note_context_block(ctx: NoteContext) -> str:
    transcript = ctx.formatted_transcription or ctx.raw_transcription
    transcript = _truncate_transcript(transcript)

    parts = [
        f"Titolo: {ctx.title}",
        f"Data: {ctx.date_time}",
        f"Tag: {ctx.tag}",
    ]

    key_data = ctx.key_data or {}
    location = str(key_data.get("location", "")).strip()
    participants = key_data.get("participants", [])
    if location:
        parts.append(f"Luogo: {location}")
    if isinstance(participants, list) and participants:
        parts.append(f"Partecipanti: {', '.join(str(p) for p in participants)}")

    if ctx.summary.strip():
        parts.append(f"\n## Riepilogo\n{ctx.summary.strip()}")

    if ctx.highlights:
        bullets = "\n".join(f"- {h}" for h in ctx.highlights)
        parts.append(f"\n## Highlights\n{bullets}")

    if ctx.mind_map:
        outline = _mind_map_outline(ctx.mind_map)
        if outline:
            parts.append(f"\n## Mind map\n{outline}")

    if ctx.speaker_view:
        blocks = []
        for block in ctx.speaker_view[:20]:
            if not isinstance(block, dict):
                continue
            speaker = block.get("speaker", "Speaker")
            text = block.get("text", "")
            if text:
                blocks.append(f"{speaker}: {text}")
        if blocks:
            parts.append("\n## Speaker view\n" + "\n".join(blocks))

    if transcript.strip():
        parts.append(f"\n## Trascrizione\n{transcript.strip()}")

    return "\n".join(parts)


def _build_openrouter_messages(request: NoteChatRequest) -> list[dict[str, str]]:
    context_block = _build_note_context_block(request.note_context)
    language_label = display_name(request.output_language) or "English"
    system_prompt = NOTE_CHAT_SYSTEM_PROMPT.format(output_language=language_label)
    system_content = (
        f"{system_prompt}\n\n"
        f"--- NOTE CONTEXT ---\n{context_block}\n--- END CONTEXT ---"
    )

    messages: list[dict[str, str]] = [{"role": "system", "content": system_content}]

    history = request.history[-MAX_HISTORY_MESSAGES:]
    for item in history:
        messages.append({"role": item.role, "content": item.content})

    messages.append({"role": "user", "content": request.message.strip()})
    return messages


def _extract_reasoning_delta(delta: dict[str, Any]) -> str:
    reasoning = delta.get("reasoning")
    if isinstance(reasoning, str) and reasoning:
        return reasoning

    details = delta.get("reasoning_details")
    if not isinstance(details, list):
        return ""

    parts: list[str] = []
    for detail in details:
        if not isinstance(detail, dict):
            continue
        if detail.get("type") == "reasoning.text":
            text = detail.get("text")
            if isinstance(text, str) and text:
                parts.append(text)
    return "".join(parts)


def _sse_event(payload: dict[str, Any]) -> str:
    return f"data: {json.dumps(payload, ensure_ascii=False)}\n\n"


async def stream_note_chat(request: NoteChatRequest) -> AsyncIterator[str]:
    if not OPENROUTER_API_KEY:
        yield _sse_event({"type": "error", "message": "OPENROUTER_API_KEY is not configured"})
        yield "data: [DONE]\n\n"
        return

    if not request.message.strip():
        yield _sse_event({"type": "error", "message": "Message is empty"})
        yield "data: [DONE]\n\n"
        return

    resolved_model = resolve_llm_model(request.ai_model)
    messages = _build_openrouter_messages(request)

    headers = {
        "Authorization": f"Bearer {OPENROUTER_API_KEY}",
        "Content-Type": "application/json",
        "HTTP-Referer": APP_REFERER,
        "X-Title": APP_TITLE,
    }

    payload = {
        "model": resolved_model,
        "stream": True,
        "reasoning": {"effort": "medium"},
        "messages": messages,
    }

    full_reasoning = ""
    full_content = ""

    try:
        async with httpx.AsyncClient(timeout=CHAT_TIMEOUT_SECONDS) as client:
            async with client.stream(
                "POST",
                OPENROUTER_CHAT_URL,
                json=payload,
                headers=headers,
            ) as response:
                if response.is_error:
                    body = await response.aread()
                    yield _sse_event({
                        "type": "error",
                        "message": f"OpenRouter error {response.status_code}: {body.decode()}",
                    })
                    yield "data: [DONE]\n\n"
                    return

                async for line in response.aiter_lines():
                    if not line:
                        continue
                    if line.startswith(":"):
                        continue
                    if not line.startswith("data: "):
                        continue

                    data_str = line[6:].strip()
                    if data_str == "[DONE]":
                        break

                    try:
                        chunk = json.loads(data_str)
                    except json.JSONDecodeError:
                        continue

                    if chunk.get("error"):
                        err = chunk["error"]
                        message = err.get("message", str(err)) if isinstance(err, dict) else str(err)
                        yield _sse_event({"type": "error", "message": message})
                        yield "data: [DONE]\n\n"
                        return

                    choices = chunk.get("choices")
                    if not isinstance(choices, list) or not choices:
                        continue

                    delta = choices[0].get("delta", {})
                    if not isinstance(delta, dict):
                        continue

                    reasoning_delta = _extract_reasoning_delta(delta)
                    if reasoning_delta:
                        full_reasoning += reasoning_delta
                        yield _sse_event({"type": "reasoning", "delta": reasoning_delta})

                    content_delta = delta.get("content")
                    if isinstance(content_delta, str) and content_delta:
                        full_content += content_delta
                        yield _sse_event({"type": "content", "delta": content_delta})

    except httpx.HTTPError as exc:
        yield _sse_event({"type": "error", "message": f"Stream failed: {exc}"})
        yield "data: [DONE]\n\n"
        return

    yield _sse_event({
        "type": "done",
        "reasoning": full_reasoning,
        "content": full_content,
    })
    yield "data: [DONE]\n\n"
