"""Lingue supportate per trascrizione (Whisper) e output dell'analisi."""

from __future__ import annotations

LANGUAGES: list[dict[str, str]] = [
    {"id": "italian", "code": "it", "label": "Italiano", "whisper": "italian"},
    {"id": "english", "code": "en", "label": "English", "whisper": "english"},
    {"id": "spanish", "code": "es", "label": "Español", "whisper": "spanish"},
    {"id": "french", "code": "fr", "label": "Français", "whisper": "french"},
    {"id": "german", "code": "de", "label": "Deutsch", "whisper": "german"},
    {"id": "portuguese", "code": "pt", "label": "Português", "whisper": "portuguese"},
    {"id": "dutch", "code": "nl", "label": "Nederlands", "whisper": "dutch"},
    {"id": "polish", "code": "pl", "label": "Polski", "whisper": "polish"},
    {"id": "romanian", "code": "ro", "label": "Română", "whisper": "romanian"},
    {"id": "russian", "code": "ru", "label": "Русский", "whisper": "russian"},
    {"id": "chinese", "code": "zh", "label": "中文", "whisper": "chinese"},
    {"id": "japanese", "code": "ja", "label": "日本語", "whisper": "japanese"},
    {"id": "korean", "code": "ko", "label": "한국어", "whisper": "korean"},
    {"id": "arabic", "code": "ar", "label": "العربية", "whisper": "arabic"},
    {"id": "hindi", "code": "hi", "label": "हिन्दी", "whisper": "hindi"},
    {"id": "turkish", "code": "tr", "label": "Türkçe", "whisper": "turkish"},
]

_BY_ID = {item["id"]: item for item in LANGUAGES}
_BY_CODE = {item["code"]: item for item in LANGUAGES}
_BY_WHISPER = {item["whisper"]: item for item in LANGUAGES}
_BY_LABEL = {item["label"].casefold(): item for item in LANGUAGES}

AUTOMATIC_IDS = {"automatic", "automatico", "auto"}

LANGUAGE_CODES: dict[str, str | None] = {
    "automatic": None,
    "automatico": None,
    "auto": None,
}
for item in LANGUAGES:
    LANGUAGE_CODES[item["id"]] = item["code"]
    LANGUAGE_CODES[item["whisper"]] = item["code"]
    LANGUAGE_CODES[item["label"].casefold()] = item["code"]
    LANGUAGE_CODES[item["code"]] = item["code"]


def whisper_code(language: str | None) -> str | None:
    if language is None:
        return None
    key = language.strip().casefold()
    if not key or key in AUTOMATIC_IDS:
        return None
    if key in LANGUAGE_CODES:
        return LANGUAGE_CODES[key]
    if len(key) == 2:
        return key
    return None


def normalize_language_id(language: str | None) -> str | None:
    """Restituisce l'id interno (italian, english, ...) o 'automatic'."""
    if language is None:
        return None
    key = language.strip().casefold()
    if not key:
        return None
    if key in AUTOMATIC_IDS:
        return "automatic"
    if key in _BY_ID:
        return key
    if key in _BY_CODE:
        return _BY_CODE[key]["id"]
    if key in _BY_WHISPER:
        return _BY_WHISPER[key]["id"]
    if key in _BY_LABEL:
        return _BY_LABEL[key]["id"]
    return None


def display_name(language: str | None) -> str | None:
    lang_id = normalize_language_id(language)
    if lang_id is None or lang_id == "automatic":
        return None
    item = _BY_ID.get(lang_id)
    return item["label"] if item else language


def resolve_detected(raw: str | None) -> str | None:
    return normalize_language_id(raw)
