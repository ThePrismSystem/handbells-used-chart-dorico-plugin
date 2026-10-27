"""The run's guards in Dorico, on scratch copies (needs Dorico running with the Remote Control API).

    python tests/dorico/test_guards.py
"""
import json
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "dorico"))
import run_lua  # noqa: E402

HERE = Path(__file__).resolve().parent
FIXTURE = ROOT / "fixtures" / "handbells-fixture.dorico"
XML = ROOT / "fixtures" / "build" / "handbells-fixture.musicxml"


def run_case(test, case, open_file, args=None, timeout=240):
    code, result, _ = run_lua.run(HERE / case, open_file=open_file, extra_args=args or {}, timeout=timeout)
    test.assertIsNotNone(result, f"{case} wrote no result (exit {code})")
    test.assertTrue(result.get("ok"), json.dumps(result, indent=1)[:4000])
    return result


class GuardTests(unittest.TestCase):
    def test_never_saved_import_is_refused(self):
        if not XML.exists():
            subprocess.run([sys.executable, str(ROOT / "fixtures" / "make_fixture_xml.py")], check=True)
        run_case(self, "case_guards.lua", XML, {"expect": "notSaved"})

    def test_saved_fixture_passes(self):
        run_case(self, "case_guards.lua", FIXTURE, {"expect": "ok"})


if __name__ == "__main__":
    unittest.main()
