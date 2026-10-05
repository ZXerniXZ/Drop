import sys
import types
import unittest

if "httpx" not in sys.modules:
    sys.modules["httpx"] = types.ModuleType("httpx")
if "dotenv" not in sys.modules:
    dotenv = types.ModuleType("dotenv")
    dotenv.load_dotenv = lambda *args, **kwargs: None
    sys.modules["dotenv"] = dotenv

from services.llm_service import _normalize_mind_map


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
        self.assertEqual(len(visuals), 1)
        self.assertEqual(visuals[0]["kind"], "chart")
        self.assertEqual(visuals[0]["labels"], ["A", "B"])
        self.assertEqual(visuals[0]["series"][0]["values"], [1, 2])

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


if __name__ == "__main__":
    unittest.main()
