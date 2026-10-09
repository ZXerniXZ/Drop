import sys
import types
import unittest

if "httpx" not in sys.modules:
    sys.modules["httpx"] = types.ModuleType("httpx")
if "dotenv" not in sys.modules:
    dotenv = types.ModuleType("dotenv")
    dotenv.load_dotenv = lambda *args, **kwargs: None
    sys.modules["dotenv"] = dotenv
if "pydantic" not in sys.modules:
    pydantic = types.ModuleType("pydantic")

    class BaseModel:
        pass

    def Field(*args, **kwargs):
        return None

    pydantic.BaseModel = BaseModel
    pydantic.Field = Field
    sys.modules["pydantic"] = pydantic

from services.chat_service import NOTE_CHAT_SYSTEM_PROMPT


class ChatPromptTest(unittest.TestCase):
    def test_prompt_allows_math_and_plots(self):
        text = NOTE_CHAT_SYSTEM_PROMPT.format(output_language="Italiano")
        self.assertIn("Italiano", text)
        self.assertIn("$...$", text)
        self.assertIn("drop-visual", text)
        self.assertIn('"kind":"plot2d"', text)
        self.assertIn('"kind":"chart"', text)
        self.assertNotIn("{output_language}", text)
        self.assertNotIn("{{", text)


if __name__ == "__main__":
    unittest.main()
