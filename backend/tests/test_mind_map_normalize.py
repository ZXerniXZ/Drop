import sys
import types
import unittest

if "httpx" not in sys.modules:
    sys.modules["httpx"] = types.ModuleType("httpx")
if "dotenv" not in sys.modules:
    dotenv = types.ModuleType("dotenv")
    dotenv.load_dotenv = lambda *args, **kwargs: None
    sys.modules["dotenv"] = dotenv

from services.llm_service import _message_text, _normalize_mind_map, apply_analysis_removal


class MindMapNormalizeTest(unittest.TestCase):
    def test_keeps_valid_visuals(self):
        nodes = _normalize_mind_map(
            [
                {
                    "title": "Parabola",
                    "body": "Si apre verso l'alto.",
                    "visuals": [
                        {
                            "kind": "plot2d",
                            "title": "Sezione",
                            "expressions": ["x^2"],
                            "x": [-2, 2],
                        },
                        {
                            "kind": "surface3d",
                            "expression": "x^2+y^2",
                            "x": [2, -2],
                            "y": [-1, 1],
                        },
                    ],
                }
            ]
        )
        self.assertEqual(len(nodes), 1)
        visuals = nodes[0]["visuals"]
        self.assertEqual(visuals[0]["kind"], "plot2d")
        self.assertEqual(visuals[0]["x"], [-2, 2])
        self.assertEqual(visuals[1]["x"], [-2.0, 2.0])

    def test_drops_unknown_kind_and_bad_ranges(self):
        nodes = _normalize_mind_map(
            [
                {
                    "title": "Punto",
                    "visuals": [
                        {"kind": "pie", "labels": ["A"]},
                        {"kind": "plot2d", "expressions": ["x"], "x": ["a", "b"]},
                        {
                            "kind": "plot2d",
                            "expressions": ["y = x"],
                            "x": [0, 1],
                        },
                        {
                            "kind": "chart",
                            "type": "line",
                            "labels": ["A", "B", "C"],
                            "series": [{"name": "v", "values": [1, 2]}],
                        },
                    ],
                }
            ]
        )
        visuals = nodes[0]["visuals"]
        self.assertEqual(len(visuals), 2)
        self.assertEqual(visuals[0]["kind"], "plot2d")
        self.assertEqual(visuals[0]["expressions"], ["x"])
        self.assertEqual(visuals[1]["kind"], "chart")
        self.assertEqual(visuals[1]["labels"], ["A", "B"])
        self.assertEqual(visuals[1]["series"][0]["values"], [1, 2])

    def test_cleans_expression_notation(self):
        nodes = _normalize_mind_map(
            [
                {
                    "title": "Curve",
                    "visuals": [
                        {
                            "kind": "plot2d",
                            "expressions": ["f(x) = 2·x² − 1", "x >= 1", "import(x)"],
                            "x": [-1, 1],
                        },
                    ],
                }
            ]
        )
        self.assertEqual(nodes[0]["visuals"][0]["expressions"], ["2*x^2 - 1"])

    def test_limits_depth_and_visual_count(self):
        deep = {"title": "L4", "children": [{"title": "L5"}]}
        node = {"title": "L1", "children": [{"title": "L2", "children": [{"title": "L3", "children": [deep]}]}]}
        nodes = _normalize_mind_map([node])
        level3 = nodes[0]["children"][0]["children"][0]
        level4 = level3["children"][0]
        self.assertEqual(level4["title"], "L4")
        self.assertEqual(level4["children"], [])

        crowded = {
            "title": "Troppi",
            "visuals": [
                {"kind": "plot2d", "expressions": ["x"], "x": [0, 1]},
                {"kind": "plot2d", "expressions": ["x^2"], "x": [0, 1]},
                {"kind": "plot2d", "expressions": ["x^3"], "x": [0, 1]},
            ],
        }
        kept = _normalize_mind_map([crowded])[0]["visuals"]
        self.assertEqual(len(kept), 2)

    def test_reads_json_from_reasoning_when_content_is_empty(self):
        text = _message_text(
            {
                "content": "",
                "reasoning": '{"mind_map": [{"title": "Nodo"}]}',
            }
        )
        self.assertIn('"title": "Nodo"', text)

        parts = _message_text(
            {"content": [{"type": "text", "text": '{"ok": true}'}]}
        )
        self.assertEqual(parts, '{"ok": true}')

    def test_removing_one_analysis_does_not_touch_the_others(self):
        class Note:
            summary = "## Vecchio"
            highlights = ["Un punto"]
            speaker_view = [{"speaker": "Ada", "text": "Ciao"}]
            mind_map = [{"title": "Nodo"}]
            key_data = {"location": "Aula"}
            raw_transcription = "Ciao dal microfono"
            formatted_transcription = "Ada: Ciao"
            analysis_state = {"highlights": "ready", "speakers": "ready"}

        note = Note()
        apply_analysis_removal(note, "speakers")
        self.assertEqual(note.speaker_view, [])
        self.assertEqual(note.formatted_transcription, "Ciao dal microfono")
        self.assertEqual(note.highlights, ["Un punto"])
        self.assertEqual(note.mind_map, [{"title": "Nodo"}])
        self.assertEqual(note.analysis_state["speakers"], "removed")
        self.assertEqual(note.analysis_state["highlights"], "ready")


if __name__ == "__main__":
    unittest.main()
