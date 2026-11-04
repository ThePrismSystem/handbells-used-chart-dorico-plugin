"""tests/dialog/launch.py: how the Windows dialog tests start dialog/windows.ps1."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import launch  # noqa: E402

START = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File"]


class LaunchTests(unittest.TestCase):
    def test_runs_the_dialog_itself(self):
        self.assertEqual(launch.command(["-Message", "m.json"], {}), [*START, str(launch.PS1), "-Message", "m.json"])

    def test_goes_through_pester_when_measuring(self):
        argv = launch.command(["-Request", "r.json", "-Response", "a.json"], {"HBUC_PS_COVERAGE": "C:/cov"})
        self.assertEqual(argv[:len(START) + 1], [*START, str(launch.COVERED)])
        out = Path(argv[argv.index("-Out") + 1])
        self.assertEqual(out.parent, Path("C:/cov"))
        self.assertEqual(out.suffix, ".xml")
        self.assertEqual(argv[-4:], ["-Request", "r.json", "-Response", "a.json"])

    def test_each_run_gets_its_own_report(self):
        env = {"HBUC_PS_COVERAGE": "C:/cov"}
        first, second = launch.command([], env), launch.command([], env)
        self.assertNotEqual(first[first.index("-Out") + 1], second[second.index("-Out") + 1])


if __name__ == "__main__":
    unittest.main()
