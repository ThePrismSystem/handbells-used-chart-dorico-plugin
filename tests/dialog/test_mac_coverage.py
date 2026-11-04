"""instrument_mac.js and mac_coverage.js, which measure the Mac dialog's osascript runs, checked under Node.

    python tests/dialog/test_mac_coverage.py

They need Node and the istanbul packages that npm ci installs, and skip without them.
"""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
MAC_JS = ROOT / "plugin" / "Handbells Used Chart" / "dialog" / "mac.js"
REPO_PATH = "plugin/Handbells Used Chart/dialog/mac.js"
HARNESS = HERE / "mac_harness.js"
INSTRUMENT = HERE / "instrument_mac.js"
MERGE = HERE / "mac_coverage.js"
NODE = shutil.which("node")


class MacCoverageTests(unittest.TestCase):
    def setUp(self):
        if not NODE:
            self.skipTest("Node is not installed")
        if not (ROOT / "node_modules" / "istanbul-lib-instrument").is_dir():
            self.skipTest("npm ci has not been run")
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.copy = self.tmp / "mac.js"
        proc = self.node(INSTRUMENT, MAC_JS, self.copy)
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def node(self, *args, env=None):
        return subprocess.run([NODE, *map(str, args)], capture_output=True, text=True, env=env)

    def jxa_run(self, report, *argv):
        """The instrumented copy's run(argv), with stand-ins for osascript's bridge and no AppKit."""
        return self.node(HARNESS, self.copy, "jxa-run", *argv, env={**os.environ, "HBUC_COVERAGE": str(report)})

    def test_instrumented_copy_answers_as_the_original(self):
        request = self.tmp / "request.json"
        request.write_text(json.dumps({"runId": "r1", "instruments": ["A", "B"], "selected": ["A"],
                                       "modes": ["One combined chart"], "mode": "One combined chart"}),
                           encoding="utf-8")
        answers = []
        for script in (MAC_JS, self.copy):
            out = self.tmp / f"answer-{len(answers)}.json"
            proc = self.node(HARNESS, script, "respond", request, out)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            answers.append(json.loads(out.read_text(encoding="utf-8")))
        self.assertEqual(answers[0], answers[1])
        self.assertEqual(answers[1]["instruments"], ["A"])

    def test_counts_are_written_when_run_ends_in_an_error(self):
        # the first AppKit call fails under Node, as any failure inside osascript would end run()
        report = self.tmp / "coverage-1.json"
        proc = self.jxa_run(report, "--message", self.tmp / "message.json")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("no AppKit", proc.stderr)
        (path, counts), = json.loads(report.read_text(encoding="utf-8")).items()
        self.assertEqual(Path(path), MAC_JS)
        self.assertGreater(sum(counts["s"].values()), 0, "the statements that ran are counted")

    def test_reports_merge_into_one_lcov_with_repo_paths(self):
        reports = self.tmp / "reports"
        reports.mkdir()
        for n in (1, 2):
            self.jxa_run(reports / f"coverage-{n}.json", "--message", self.tmp / "message.json")
        out = self.tmp / "lcov"
        proc = self.node(MERGE, reports, out)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        lines = (out / "lcov.info").read_text(encoding="utf-8").splitlines()
        self.assertEqual([x for x in lines if x.startswith("SF:")], [f"SF:{REPO_PATH}"])
        cocoa = next(i for i, x in enumerate(MAC_JS.read_text(encoding="utf-8").splitlines(), 1)
                     if 'ObjC.import("Cocoa")' in x)
        self.assertIn(f"DA:{cocoa},2", lines, "both runs reached the first line of run()")

    def test_no_reports_is_an_error(self):
        empty = self.tmp / "empty"
        empty.mkdir()
        proc = self.node(MERGE, empty, self.tmp / "lcov")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("no coverage reports", proc.stderr)

    def harness(self, script, reports, *args):
        return self.node(HARNESS, script, *args, env={**os.environ, "HBUC_JS_COVERAGE": str(reports)})

    def test_node_runs_of_mac_js_are_counted_when_measuring(self):
        # as the osascript runs are, so that Codecov merges two reports that count the same lines
        reports = self.tmp / "node-runs"
        reports.mkdir()
        proc = self.harness(MAC_JS, reports, "eval", "chartsEnabled([true, true])")
        self.assertEqual(proc.stdout, "true", proc.stderr)
        (report,) = reports.glob("coverage-*.json")
        (path, counts), = json.loads(report.read_text(encoding="utf-8")).items()
        self.assertEqual(Path(path), MAC_JS)
        self.assertGreater(sum(counts["s"].values()), 0)

    def test_only_the_plugin_is_counted(self):
        reports = self.tmp / "node-runs"
        reports.mkdir()
        self.harness(self.copy, reports, "eval", "1")
        self.harness(HERE / "mac_drive.js", reports, "eval", "1")
        self.assertEqual(list(reports.iterdir()), [], "the copy counts for itself, and the driver is a test")

    def test_nothing_is_written_without_a_folder(self):
        env = {k: v for k, v in os.environ.items() if k != "HBUC_JS_COVERAGE"}
        proc = self.node(HARNESS, MAC_JS, "eval", "1", env=env)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(list(self.tmp.glob("**/coverage-*.json")), [])


if __name__ == "__main__":
    unittest.main()
