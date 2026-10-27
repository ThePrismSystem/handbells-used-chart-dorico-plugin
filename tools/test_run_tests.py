"""tools/run_tests.py's own helpers."""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_tests  # noqa: E402


class FindLuaTests(unittest.TestCase):
    def test_only_lua_5_2_is_taken(self):
        # a plain "lua" on the PATH may be 5.3 or 5.4, whose integers and libraries differ
        versions = {"lua52": None, "lua5.2": None, "lua": "Lua 5.4"}
        with mock.patch.object(run_tests, "LUA_CANDIDATES", ["lua52", "lua5.2", "lua"]), \
                mock.patch("shutil.which", side_effect=lambda c: c if versions.get(c) else None), \
                mock.patch.object(run_tests, "lua_version", side_effect=lambda exe: versions[exe]):
            self.assertIsNone(run_tests.find_lua())
        versions["lua"] = "Lua 5.2"
        with mock.patch.object(run_tests, "LUA_CANDIDATES", ["lua52", "lua5.2", "lua"]), \
                mock.patch("shutil.which", side_effect=lambda c: c if versions.get(c) else None), \
                mock.patch.object(run_tests, "lua_version", side_effect=lambda exe: versions[exe]):
            self.assertEqual(run_tests.find_lua(), "lua")


if __name__ == "__main__":
    unittest.main()
