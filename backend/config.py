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
