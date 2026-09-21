import os

from dotenv import load_dotenv

load_dotenv()

OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY", "")
OPENROUTER_LLM_MODEL = os.getenv(
    "OPENROUTER_LLM_MODEL", "google/gemini-3.6-flash"
)
TRANSCRIPTION_TIMEOUT_SECONDS = float(
    os.getenv("TRANSCRIPTION_TIMEOUT_SECONDS", "600")
)
LLM_TIMEOUT_SECONDS = float(os.getenv("LLM_TIMEOUT_SECONDS", "300"))
MAX_TRANSCRIPT_CHARS = int(os.getenv("MAX_TRANSCRIPT_CHARS", "100000"))
# Durata degli spezzoni inviati a Whisper: piu' corti danno un avanzamento
# misurabile all'app, piu' lunghi riducono il numero di richieste.
SEGMENT_TARGET_SECONDS = float(os.getenv("SEGMENT_TARGET_SECONDS", "300"))
# Ore di audio che un utente puo' far trascrivere con la chiave OpenRouter del server.
SERVER_AUDIO_QUOTA_SECONDS = float(os.getenv("SERVER_AUDIO_QUOTA_SECONDS", "7200"))


def _int_env(name: str, default: int) -> int:
    raw = os.getenv(name, "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


# Build più vecchie di questa vengono bloccate in app e sulle API.
MIN_APP_VERSION = os.getenv("MIN_APP_VERSION", "1.0.4").strip() or "1.0.4"
MIN_APP_BUILD = _int_env("MIN_APP_BUILD", 30)
APP_UPDATE_ANDROID_URL = os.getenv(
    "APP_UPDATE_ANDROID_URL",
    "https://github.com/ZXerniXZ/Drop/releases/latest",
).strip()
APP_UPDATE_WEB_URL = os.getenv(
    "APP_UPDATE_WEB_URL",
    "https://drop-app-3x2.pages.dev",
).strip()
APP_UPDATE_MESSAGE = os.getenv(
    "APP_UPDATE_MESSAGE",
    "Questa versione di Drop non è più supportata. Aggiorna per continuare.",
).strip()

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./drop_backend.db")
# Stesso HS256 secret di GoTrue (JWT_SECRET). URL pubblico Auth senza /auth/v1.
SUPABASE_JWT_SECRET = os.getenv("SUPABASE_JWT_SECRET", "") or os.getenv(
    "JWT_SECRET", ""
)
SUPABASE_URL = os.getenv("SUPABASE_URL", "https://auth.drop-prj.xyz").rstrip("/")
CORS_ORIGIN_REGEX = os.getenv(
    "CORS_ORIGIN_REGEX",
    r"https://app\.drop-prj\.xyz|"
    r"https://[a-z0-9.-]+\.pages\.dev|"
    r"http://localhost:\d+|"
    r"http://127\.0\.0\.1:\d+",
)
