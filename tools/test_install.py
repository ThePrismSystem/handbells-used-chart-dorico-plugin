import shutil
import sys
import tempfile
import unittest
from pathlib import Path

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


if __name__ == "__main__":
    unittest.main()
