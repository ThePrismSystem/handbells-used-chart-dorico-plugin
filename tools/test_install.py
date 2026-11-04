import io
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import install  # noqa: E402


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.target = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.target, True)

    def test_installs_the_entry_and_its_folder(self):
        install.install(self.target)
        self.assertTrue((self.target / "Handbells Used Chart.lua").is_file())
        self.assertTrue((self.target / "Handbells Used Chart" / "hbuc" / "main.lua").is_file())
        self.assertTrue((self.target / "Handbells Used Chart" / "dialog" / "windows.ps1").is_file())
        self.assertTrue((self.target / "Handbells Used Chart" / "dialog" / "mac.js").is_file())

    def test_reinstall_replaces_and_keeps_other_plugins(self):
        install.install(self.target)
        stale = self.target / "Handbells Used Chart" / "hbuc" / "stale.lua"
        stale.write_text("return 1\n")
        other = self.target / "Someone Else.lua"
        other.write_text("-- another plug-in\n")
        install.install(self.target)
        self.assertFalse(stale.exists(), "an old copy's files are gone")
        self.assertTrue(other.exists(), "nothing else in the folder is touched")

    def test_uninstall_removes_only_the_plugin(self):
        install.install(self.target)
        other = self.target / "Someone Else.lua"
        other.write_text("-- another plug-in\n")
        install.uninstall(self.target)
        self.assertFalse((self.target / "Handbells Used Chart.lua").exists())
        self.assertFalse((self.target / "Handbells Used Chart").exists())
        self.assertTrue(other.exists())

    def test_default_target_is_dorico_6_script_plugins(self):
        # the platform is named, so the test means the same on a Mac
        target = install.default_target({"APPDATA": "C:\\Users\\u\\AppData\\Roaming"}, "win32")
        self.assertEqual(target, Path("C:\\Users\\u\\AppData\\Roaming") / "Steinberg" / "Dorico 6" / "Script Plug-ins")

    def test_mac_target(self):
        target = install.default_target({"HOME": "/Users/u"}, "darwin")
        self.assertEqual(target.as_posix(), "/Users/u/Library/Application Support/Steinberg/Dorico 6/Script Plug-ins")

    def run_main(self, *args):
        with mock.patch.object(sys, "argv", ["install.py", *args]), redirect_stdout(io.StringIO()) as printed:
            code = install.main()
        return code, printed.getvalue()

    def test_main_installs_into_the_target(self):
        code, printed = self.run_main("--target", str(self.target))
        self.assertEqual(code, 0)
        self.assertTrue((self.target / "Handbells Used Chart.lua").is_file())
        self.assertIn(f"installed into {self.target}", printed)

    def test_main_uninstalls(self):
        install.install(self.target)
        code, printed = self.run_main("--target", str(self.target), "--uninstall")
        self.assertEqual(code, 0)
        self.assertFalse((self.target / "Handbells Used Chart.lua").exists())
        self.assertIn(f"removed the plug-in from {self.target}", printed)


if __name__ == "__main__":
    unittest.main()
