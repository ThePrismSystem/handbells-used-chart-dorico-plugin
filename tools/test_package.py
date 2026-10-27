import shutil
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import package  # noqa: E402


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.out = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.out, True)

    def test_zip_holds_the_plugin_and_documents(self):
        path = package.build(self.out)
        self.assertEqual(path.name, "handbells-used-chart-dorico-v0.1.0.zip")
        with zipfile.ZipFile(path) as z:
            names = set(z.namelist())
        top = "handbells-used-chart-dorico-v0.1.0/"
        for name in ("Handbells Used Chart.lua", "Handbells Used Chart/hbuc/main.lua",
                     "Handbells Used Chart/dialog/windows.ps1", "Handbells Used Chart/dialog/mac.js",
                     "README.md", "LICENSE.md", "CHANGELOG.md"):
            self.assertIn(top + name, names)
        self.assertTrue(all(n.startswith(top) for n in names), "everything is in the versioned folder")
        self.assertFalse(any("__pycache__" in n or n.endswith(".pyc") for n in names))

    def test_text_files_have_unix_line_endings(self):
        # the same zip whichever way git checked the files out
        with zipfile.ZipFile(package.build(self.out)) as z:
            for name in z.namelist():
                if name.endswith((".lua", ".js", ".ps1", ".md")):
                    self.assertNotIn(b"\r\n", z.read(name), name)

    def test_version_comes_from_constants(self):
        constants = self.out / "constants.lua"
        constants.write_text('constants.MARKER_VERSION = "1"\nconstants.VERSION = "9.8.7"\n', encoding="utf-8")
        self.assertEqual(package.version(constants), "9.8.7")
        self.assertEqual(package.version(), "0.1.0")


if __name__ == "__main__":
    unittest.main()
