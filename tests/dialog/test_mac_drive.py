"""mac_drive.js, the Mac dialog tests' driver, checked under Node: its parts that don't need System Events.

    python tests/dialog/test_mac_drive.py
"""
import json
import shutil
import subprocess
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
DRIVE = HERE / "mac_drive.js"
HARNESS = HERE / "mac_harness.js"
NODE = shutil.which("node")


class MacDriveTests(unittest.TestCase):
    def evaluate(self, expression):
        if not NODE:
            self.skipTest("Node is not installed")
        out = subprocess.run([NODE, str(HARNESS), str(DRIVE), "eval", expression], capture_output=True, text=True,
                             check=True).stdout
        return json.loads(out)

    def test_a_wait_that_runs_out_says_what_went_wrong(self):
        # System Events refusing access looks like a window that never opens unless the error is passed on
        message = self.evaluate("""(function () {
            let now = 0;
            Date = { now: function () { return now += 10000; } };
            delay = function () {};
            try {
              until("a window", function () { throw new Error("osascript is not allowed assistive access"); });
            } catch (e) {
              return e.message;
            }
          })()""")
        self.assertIn("a window did not appear within 30 s", message)
        self.assertIn("osascript is not allowed assistive access", message)

    def test_a_wait_returns_the_first_answer(self):
        self.assertEqual(self.evaluate("""(function () {
            let tries = 0;
            delay = function () {};
            return until("a window", function () { tries += 1; return tries < 3 ? null : "found " + tries; });
          })()"""), "found 3")


if __name__ == "__main__":
    unittest.main()
