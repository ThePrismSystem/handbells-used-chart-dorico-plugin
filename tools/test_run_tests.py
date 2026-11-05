"""tools/run_tests.py's own helpers."""
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
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

    def test_lua_version_survives_a_missing_exe(self):
        self.assertIsNone(run_tests.lua_version(str(Path(tempfile.gettempdir()) / "no-such-lua-here")))


class MainTests(unittest.TestCase):
    """main() with every process it starts recorded instead of run."""

    def setUp(self):
        self.out = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.out, True)
        self.calls = []
        self.codes = {}  # first argument after the interpreter -> exit code, for a suite that fails

    def fake_run(self, argv, **kw):
        self.calls.append((list(argv), kw.get("env")))
        code = next((c for key, c in self.codes.items() if key in argv), 0)
        return subprocess.CompletedProcess(argv, code, stdout="", stderr="Ran 1 test\n\nOK")

    def main(self, *argv, missing=()):
        with mock.patch.object(run_tests, "find_lua", return_value="lua"), \
                mock.patch.object(run_tests, "coverage_tools", return_value=list(missing)), \
                mock.patch.object(run_tests, "node", return_value="node"), \
                mock.patch.object(run_tests, "COVERAGE_DIR", self.out / "coverage"), \
                mock.patch("subprocess.run", side_effect=self.fake_run), redirect_stdout(io.StringIO()) as printed:
            code = run_tests.main(list(argv))
        return code, printed.getvalue()

    def argvs(self):
        return [argv for argv, _ in self.calls]

    def test_without_coverage_nothing_changes(self):
        code, _ = self.main()
        self.assertEqual(code, 0)
        self.assertEqual(self.argvs(), [[sys.executable, "-m", "unittest", *run_tests.PY_TESTS]]
                         + [["lua", t] for t in run_tests.LUA_TESTS])
        self.assertTrue(all(env is None for _, env in self.calls))

    def test_main_reports_a_failed_suite(self):
        self.codes["tests/run.lua"] = 1
        code, printed = self.main()
        self.assertEqual(code, 1)
        self.assertIn("FAIL  lua tests/run.lua", printed)
        self.assertIn("SOME FAILED", printed)

    def test_coverage_runs_each_suite_under_its_tool(self):
        cov = self.out / "coverage"
        code, _ = self.main("--coverage")
        self.assertEqual(code, 0)
        python, env = self.calls[0]
        self.assertEqual(python, [sys.executable, "-m", "coverage", "run", "-m", "unittest", *run_tests.PY_TESTS])
        self.assertEqual(env["HBUC_JS_COVERAGE"], str(cov / "js-node-runs"),
                         "the Mac script's Node runs write their counts there")
        self.assertTrue((cov / "js-node-runs").is_dir(), "made before the runs that write into it")
        argvs = self.argvs()
        self.assertIn(["lua", "-lluacov", "tests/run.lua"], argvs)
        self.assertIn(["lua", "spike/lib/test_json.lua"], argvs, "the spike's libraries aren't measured")
        self.assertIn([sys.executable, "-m", "coverage", "xml", "-o", str(cov / "python.xml")], argvs)
        self.assertIn(["lua", "-e", run_tests.LUACOV_REPORT], argvs)
        self.assertIn(["node", "tests/dialog/mac_coverage.js", str(cov / "js-node-runs"), str(cov / "js-node")], argvs,
                      "counted as the osascript runs are, so Codecov can merge the two")

    def test_coverage_starts_from_nothing(self):
        stale = self.out / "coverage" / "luacov.stats.out"
        stale.parent.mkdir(parents=True)
        stale.write_text("from an earlier run")
        self.main("--coverage")
        self.assertFalse(stale.exists(), "luacov adds to its stats file, so an old one would count twice")

    def test_dorico_adds_the_in_dorico_checks(self):
        with mock.patch.object(run_tests, "dorico_checks", return_value=False) as checks:
            code, _ = self.main("--dorico")
        checks.assert_called_once_with()
        self.assertEqual(code, 1)

    def test_coverage_without_its_tools_says_how_to_get_them(self):
        code, printed = self.main("--coverage", missing=["luarocks install luacov"])
        self.assertEqual(code, 1)
        self.assertIn("luarocks install luacov", printed)
        self.assertEqual(self.calls, [], "nothing runs")


class CoverageToolsTests(unittest.TestCase):
    def test_coverage_needs_its_tools(self):
        with mock.patch("subprocess.run", return_value=subprocess.CompletedProcess([], 1)), \
                mock.patch("importlib.util.find_spec", return_value=None), \
                mock.patch.object(run_tests, "node", return_value=None):
            hints = run_tests.coverage_tools("lua")
        self.assertEqual(len(hints), 3)
        self.assertIn("luarocks install luacov", hints[0])
        self.assertIn("luarocks install luacov-reporter-lcov", hints[0])
        self.assertIn("pip install -r requirements-dev.txt", hints[1])
        self.assertIn("npm ci", hints[2])
        self.assertIn("istanbul", hints[2])

    def test_luacov_is_missing_without_lua(self):
        with mock.patch("importlib.util.find_spec", return_value=object()), \
                mock.patch.object(run_tests, "node", return_value="node"):
            hints = run_tests.coverage_tools(None)
        self.assertEqual(len(hints), 1)
        self.assertIn("luarocks install luacov", hints[0])

    def test_all_there(self):
        with mock.patch("subprocess.run", return_value=subprocess.CompletedProcess([], 0)), \
                mock.patch("importlib.util.find_spec", return_value=object()), \
                mock.patch.object(run_tests, "node", return_value="node"):
            self.assertEqual(run_tests.coverage_tools("lua"), [])

    def test_node_counts_only_with_the_istanbul_packages(self):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root, True)
        with mock.patch.object(run_tests, "ROOT", root), mock.patch("shutil.which", return_value="/usr/bin/node"):
            self.assertIsNone(run_tests.node(), "npm ci hasn't run")
            (root / "node_modules" / "istanbul-lib-instrument").mkdir(parents=True)
            self.assertEqual(run_tests.node(), "/usr/bin/node")


class LcovPercentTests(unittest.TestCase):
    def test_counts_lines_hit_over_lines_found(self):
        out = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, out, True)
        lcov = out / "lcov.info"
        lcov.write_text("SF:a.lua\nLF:10\nLH:9\nend_of_record\nSF:b.lua\nLF:10\nLH:6\nend_of_record\n")
        self.assertEqual(run_tests.lcov_percent(lcov), 75.0)

    def test_no_report_is_none(self):
        self.assertIsNone(run_tests.lcov_percent(Path(tempfile.gettempdir()) / "no-such-report.info"))

    def test_lua_paths_are_made_relative_to_the_repo(self):
        # tests/run.lua finds the plug-in through tests/../, and Codecov matches files by their path in the repo
        out = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, out, True)
        lcov = out / "lua.lcov"
        lcov.write_text("TN:\nSF:tests/../plugin/Handbells Used Chart/hbuc/plan.lua\nDA:1,1\nend_of_record\n")
        run_tests.normalize_lcov(lcov)
        self.assertEqual(lcov.read_text(), "TN:\nSF:plugin/Handbells Used Chart/hbuc/plan.lua\nDA:1,1\nend_of_record\n")


if __name__ == "__main__":
    unittest.main()
