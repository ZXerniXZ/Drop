import os

from dotenv import load_dotenv

load_dotenv()

OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY", "")
OPENROUTER_LLM_MODEL = os.getenv(
    "OPENROUTER_LLM_MODEL", "google/gemini-flash-1.5"
)
