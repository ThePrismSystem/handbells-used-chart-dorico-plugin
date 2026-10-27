import hashlib
import io
import shutil
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

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


class TagTests(unittest.TestCase):
    def test_the_version_tag_is_a_release(self):
        self.assertEqual(package.tag_kind("v0.1.0", "0.1.0"), "release")

    def test_rc_tags_are_candidates(self):
        self.assertEqual(package.tag_kind("v0.1.0-rc.0", "0.1.0"), "candidate")
        self.assertEqual(package.tag_kind("v0.1.0-rc.12", "0.1.0"), "candidate")

    def test_other_tags_match_nothing(self):
        for tag in ("v0.1.1", "0.1.0", "v0.1.0-beta", "v0.1.0-rc.", "v0.1.0-rc.x", "v0.1.0-rc.1.2", "v0.1.00"):
            self.assertIsNone(package.tag_kind(tag, "0.1.0"), tag)


CHANGELOG = """# Changelog

## [0.2.0] - 2027-01-01

### Fixed

- Something later.

## [0.1.0] - 2026-10-26

The first version.

### Added

- The plug-in.

[0.2.0]: https://example.com/v0.2.0
[0.1.0]: https://example.com/v0.1.0
"""


class ReleaseNotesTests(unittest.TestCase):
    def notes(self):
        return package.release_notes(CHANGELOG, "0.1.0", "x-v0.1.0.zip", "ab12")

    def test_notes_hold_that_version_only(self):
        notes = self.notes()
        self.assertIn("The first version.", notes)
        self.assertIn("- The plug-in.", notes)
        self.assertNotIn("Something later", notes)
        self.assertNotIn("example.com", notes)

    def test_notes_give_the_checksum_and_how_to_verify(self):
        notes = self.notes()
        self.assertIn("SHA-256: ab12", notes)
        self.assertIn("gh attestation verify x-v0.1.0.zip --repo ThePrismSystem/handbells-used-chart-dorico-plugin "
                      "--signer-workflow ThePrismSystem/handbells-used-chart-dorico-plugin/.github/workflows/release.yml",
                      notes)

    def test_a_missing_version_is_an_error(self):
        with self.assertRaises(ValueError):
            package.release_notes(CHANGELOG, "9.9.9", "x.zip", "ab12")


class ReleaseCommandTests(unittest.TestCase):
    def setUp(self):
        self.out = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.out, True)

    def run_main(self, tag):
        notes, outputs = self.out / "notes.md", self.out / "outputs.txt"
        argv = ["--out", str(self.out / "dist"), "--tag", tag, "--notes", str(notes), "--outputs", str(outputs)]
        with mock.patch("sys.stdout", io.StringIO()), mock.patch("sys.stderr", io.StringIO()) as err:
            code = package.main(argv)
        return code, notes, outputs, err.getvalue()

    def test_a_mismatched_tag_builds_nothing(self):
        code, notes, _, err = self.run_main("v0.1.1")
        self.assertEqual(code, 1)
        self.assertIn("tag v0.1.1 does not match version 0.1.0", err)
        self.assertFalse((self.out / "dist").exists())
        self.assertFalse(notes.exists())

    def test_a_candidate_builds_the_zip_notes_and_outputs(self):
        code, notes, outputs, _ = self.run_main("v0.1.0-rc.0")
        self.assertEqual(code, 0)
        zip_path = self.out / "dist" / "handbells-used-chart-dorico-v0.1.0.zip"
        self.assertTrue(zip_path.exists())
        self.assertIn("SHA-256: " + hashlib.sha256(zip_path.read_bytes()).hexdigest(), notes.read_text(encoding="utf-8"))
        self.assertEqual(outputs.read_text(encoding="utf-8").splitlines(), [f"zip={zip_path}", "prerelease=true"])

    def test_the_release_tag_is_not_a_prerelease(self):
        _, _, outputs, _ = self.run_main("v0.1.0")
        self.assertIn("prerelease=false", outputs.read_text(encoding="utf-8").splitlines())


if __name__ == "__main__":
    unittest.main()
