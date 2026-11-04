"""tools/coverage_gate.py: a language's line coverage, merged over its reports, against the floor."""
import io
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import coverage_gate  # noqa: E402

# a.lua: line 1 hit in the first report, line 2 in the second, line 3 in neither; b.lua: its one line hit
LCOV_FIRST = "TN:\nSF:plugin/a.lua\nDA:1,1\nDA:2,0\nDA:3,0\nLF:3\nLH:1\nend_of_record\n"
LCOV_SECOND = ("TN:\nSF:plugin/a.lua\nDA:1,0\nDA:2,4\nDA:3,0\nend_of_record\n"
               "SF:plugin/b.lua\nDA:1,1\nend_of_record\n")


def cobertura(files):
    """A Cobertura report: {filename: {line: hits}}, with a method repeating its lines as Pester's do."""
    classes = ""
    for name, lines in files.items():
        rows = "".join(f'<line number="{n}" hits="{h}"/>' for n, h in lines.items())
        classes += (f'<class filename="{name}"><methods><method name="m"><lines>{rows}</lines></method></methods>'
                    f"<lines>{rows}</lines></class>")
    return f'<?xml version="1.0"?><coverage><packages><package><classes>{classes}</classes></package></packages></coverage>'


class CoverageGateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def write(self, name, text):
        path = self.tmp / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def main(self, *argv):
        with redirect_stdout(io.StringIO()) as printed:
            code = coverage_gate.main(list(map(str, argv)))
        return code, printed.getvalue()

    def test_a_line_hit_in_any_lcov_report_counts(self):
        first, second = self.write("first.info", LCOV_FIRST), self.write("second.info", LCOV_SECOND)
        self.assertEqual(coverage_gate.lines([first, second]), (3, 4))

    def test_a_line_hit_in_any_cobertura_report_counts(self):
        first = self.write("first.xml", cobertura({"windows.ps1": {1: 1, 2: 0, 3: 0}}))
        second = self.write("second.xml", cobertura({"windows.ps1": {1: 0, 2: 3, 3: 0}}))
        self.assertEqual(coverage_gate.lines([first, second]), (2, 3))

    def test_a_folder_stands_for_every_report_in_it(self):
        self.write("ps/coverage-1.xml", cobertura({"windows.ps1": {1: 1, 2: 0}}))
        self.write("ps/coverage-2.xml", cobertura({"windows.ps1": {2: 1}}))
        self.write("ps/notes.txt", "not a report")
        self.assertEqual(coverage_gate.lines([self.tmp / "ps"]), (2, 2))

    def test_at_the_floor_passes(self):
        report = self.write("lua.lcov", "SF:a.lua\nDA:1,1\nDA:2,1\nDA:3,1\nDA:4,1\nDA:5,0\nend_of_record\n")
        code, printed = self.main("lua", report)
        self.assertEqual(code, 0)
        self.assertIn("lua: 80.0% of 5 lines covered", printed)

    def test_under_the_floor_fails(self):
        report = self.write("python.xml", cobertura({"tools/x.py": {n: int(n <= 79) for n in range(1, 101)}}))
        code, printed = self.main("python", report)
        self.assertEqual(code, 1)
        self.assertIn("python: 79.0% of 100 lines covered", printed)
        self.assertIn("under the 80% floor", printed)

    def test_a_missing_report_is_an_error(self):
        code, printed = self.main("javascript", self.tmp / "js-mac" / "lcov.info")
        self.assertEqual(code, 2)
        self.assertIn("not found", printed)

    def test_reports_with_no_lines_are_an_error(self):
        (self.tmp / "empty").mkdir()
        code, printed = self.main("powershell", self.tmp / "empty")
        self.assertEqual(code, 2)
        self.assertIn("no lines", printed)


if __name__ == "__main__":
    unittest.main()
