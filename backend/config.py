import os

from dotenv import load_dotenv

load_dotenv()

OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY", "")
OPENROUTER_LLM_MODEL = os.getenv(
    "OPENROUTER_LLM_MODEL", "google/gemini-3.5-flash"
)
TRANSCRIPTION_TIMEOUT_SECONDS = float(
    os.getenv("TRANSCRIPTION_TIMEOUT_SECONDS", "600")
)
LLM_TIMEOUT_SECONDS = float(os.getenv("LLM_TIMEOUT_SECONDS", "300"))

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./drop_backend.db")
SUPABASE_JWT_SECRET = os.getenv("SUPABASE_JWT_SECRET", "")
SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
