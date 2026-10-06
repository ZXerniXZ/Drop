import sys
import types

if "fastapi" not in sys.modules:
    fastapi = types.ModuleType("fastapi")

    class HTTPException(Exception):
        def __init__(self, status_code: int = 400, detail: str = "") -> None:
            super().__init__(detail)
            self.status_code = status_code
            self.detail = detail

    fastapi.HTTPException = HTTPException
    sys.modules["fastapi"] = fastapi

if "sqlalchemy" not in sys.modules:
    sqlalchemy = types.ModuleType("sqlalchemy")
    sqlalchemy.select = lambda *args, **kwargs: None
    sys.modules["sqlalchemy"] = sqlalchemy

if "sqlalchemy.orm" not in sys.modules:
    orm = types.ModuleType("sqlalchemy.orm")
    orm.Session = object
    sys.modules["sqlalchemy.orm"] = orm

if "models" not in sys.modules:
    sys.modules["models"] = types.ModuleType("models")
if "models.note" not in sys.modules:
    note = types.ModuleType("models.note")
    note.NoteDB = object
    sys.modules["models.note"] = note
if "models.note_folder" not in sys.modules:
    folder = types.ModuleType("models.note_folder")
    folder.NoteFolderDB = object
    sys.modules["models.note_folder"] = folder

import unittest

from services.folder_service import collect_subtree_ids


class FolderTreeTest(unittest.TestCase):
    def test_subtree_includes_nested_folders(self):
        parents = {
            "root": None,
            "child": "root",
            "leaf": "child",
            "other": None,
        }

        self.assertEqual(
            collect_subtree_ids(parents, "root"),
            {"root", "child", "leaf"},
        )
        self.assertEqual(
            collect_subtree_ids(parents, "child"),
            {"child", "leaf"},
        )
        self.assertEqual(collect_subtree_ids(parents, "other"), {"other"})
