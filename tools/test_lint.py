"""tools/lint.py: the runner and its helpers."""
import contextlib
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lint  # noqa: E402


def quietly(fn, *args, **kw):
    """fn's result and what it printed."""
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        result = fn(*args, **kw)
    return result, out.getvalue()


def fake(name="fake", clean=True, optional=False, calls=None):
    def run(exe, sarif_dir):
        if calls is not None:
            calls.append(name)
        return clean
    return lint.Tool(name, name + "-exe", "pip install " + name, run, optional=optional)


def temp_repo(test):
    tmp = Path(tempfile.mkdtemp())
    test.addCleanup(shutil.rmtree, tmp, True)
    subprocess.run(["git", "init", "-q", str(tmp)], check=True)
    return tmp


class TrackedTests(unittest.TestCase):
    def test_only_tracked_files_are_listed(self):
        tmp = temp_repo(self)
        folder = tmp / "dir with space"
        folder.mkdir()
        (folder / "a.lua").write_text("return 1\n")
        (folder / "b.lua").write_text("return 2\n")
        subprocess.run(["git", "add", "dir with space/a.lua"], cwd=tmp, check=True)
        self.assertEqual(lint.tracked(["*.lua"], cwd=tmp), ["dir with space/a.lua"])


class RunToolTests(unittest.TestCase):
    def test_missing_tool_is_a_skip(self):
        with mock.patch.object(lint, "find_exe", return_value=None):
            status, printed = quietly(lint.run_tool, fake(), strict=False, sarif_dir=None)
        self.assertEqual(status, "SKIP")
        self.assertIn("pip install fake", printed)

    def test_missing_tool_fails_when_strict(self):
        with mock.patch.object(lint, "find_exe", return_value=None):
            status, _ = quietly(lint.run_tool, fake(), strict=True, sarif_dir=None)
        self.assertEqual(status, "FAIL")

    def test_findings_fail(self):
        with mock.patch.object(lint, "find_exe", return_value="/bin/fake"):
            status, printed = quietly(lint.run_tool, fake(clean=False), strict=False, sarif_dir=None)
        self.assertEqual(status, "FAIL")
        self.assertIn("FAIL  fake", printed)

    def test_clean_passes(self):
        with mock.patch.object(lint, "find_exe", return_value="/bin/fake"):
            status, printed = quietly(lint.run_tool, fake(), strict=False, sarif_dir=None)
        self.assertEqual(status, "PASS")
        self.assertIn("PASS  fake", printed)

    def test_node_modules_bin_comes_first(self):
        def which(name, path=None):
            return os.path.join(path, name) if path else "/usr/bin/" + name
        with mock.patch("shutil.which", side_effect=which):
            self.assertEqual(lint.find_exe("eslint"), str(lint.ROOT / "node_modules" / ".bin" / "eslint"))


class MainTests(unittest.TestCase):
    def main(self, tools, argv):
        with mock.patch.object(lint, "TOOLS", tools), mock.patch.object(lint, "find_exe", return_value="/bin/x"):
            return quietly(lint.main, argv)[0]

    def test_any_failure_fails_the_run(self):
        self.assertEqual(self.main([fake("a"), fake("b", clean=False)], []), 1)

    def test_all_clean_passes(self):
        self.assertEqual(self.main([fake("a"), fake("b")], []), 0)

    def test_only_runs_the_named_tools(self):
        calls = []
        self.main([fake("a", calls=calls), fake("b", calls=calls)], ["--only", "a"])
        self.assertEqual(calls, ["a"])

    def test_optional_tools_wait_to_be_asked(self):
        calls = []
        tools = [fake("a", calls=calls), fake("slow", optional=True, calls=calls)]
        self.main(tools, [])
        self.assertEqual(calls, ["a"])
        self.main(tools, ["--codeql"])
        self.assertEqual(calls, ["a", "a", "slow"])


class RuffTests(unittest.TestCase):
    def test_paths_with_spaces_stay_one_argument(self):
        ruff = next(t for t in lint.TOOLS if t.name == "ruff")
        with mock.patch.object(lint, "tracked", return_value=["plugin/Handbells Used Chart/x.py"]), \
                mock.patch("subprocess.run", return_value=subprocess.CompletedProcess([], 0)) as run:
            self.assertTrue(ruff.run("ruff", None))
        argv = run.call_args.args[0]
        self.assertEqual(argv[:3], ["ruff", "check", "--no-fix"])
        self.assertIn("plugin/Handbells Used Chart/x.py", argv)


if __name__ == "__main__":
    unittest.main()
