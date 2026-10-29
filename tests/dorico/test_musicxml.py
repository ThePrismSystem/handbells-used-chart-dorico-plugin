"""Noteheads changed in Dorico, read from a MusicXML export, in Dorico on scratch copies of the fixture. Dorico's own
Export MusicXML, Delete Flow and Delete Empty Players dialogs are answered from here through UI Automation.

    python tests/dorico/test_musicxml.py
"""
import shutil
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import harness  # noqa: E402
import run_lua  # noqa: E402

CHIMES = {"sets": ["noteheadset.diamondNoteheads"]}


def clear_exports():
    # Dorico asks before overwriting an earlier export's files
    for folder in run_lua.RUN_DIR.glob("Flows from *"):
        shutil.rmtree(folder)


class MusicXMLTests(unittest.TestCase):
    def setUp(self):
        clear_exports()
        self.addCleanup(clear_exports)

    def exporting(self, client, args):
        """case_musicxml.lua in the background, with OK pressed in Dorico's export dialog."""
        running = harness.Background(lambda: harness.run_more(self, client, "case_musicxml.lua", args, expect_ok=False))
        self.assertEqual(harness.wait_for_window(title="Export MusicXML"), "Export MusicXML")
        self.assertTrue(harness.click("Export MusicXML", "OK"))
        return harness.check(self, running.join(600), "case_musicxml.lua")

    def test_readable_heads_ask_nothing(self):
        with harness.scratch(self, "case_musicxml.lua", args={"expect": "asksNothing"}):
            pass

    def test_unreadable_heads_are_read_from_the_export(self):
        with harness.scratch(self, "case_heads.lua", args=CHIMES) as (client, _):
            self.exporting(client, {"choose": ["export"], "pick": "preselected", "expect": "drawn"})

    def test_another_players_part_is_refused(self):
        # the chimes are Handbells (A)'s: the Organ's part holds none of its notes
        with harness.scratch(self, "case_heads.lua", args=CHIMES) as (client, _):
            self.exporting(client, {"choose": ["export"], "pick": "organ", "expect": "mismatch"})

    def test_remove_from_the_message(self):
        with harness.scratch(self, "case_write.lua", args={"mode": "combined"}) as (client, _):
            harness.run_more(self, client, "case_heads.lua", CHIMES)
            removing = harness.Background(lambda: harness.run_more(
                self, client, "case_musicxml.lua", {"choose": ["remove"], "expect": "removed"}, expect_ok=False))
            self.assertEqual(harness.wait_for_window(title="Delete Flow"), "Delete Flow")
            self.assertTrue(harness.click("Delete Flow", "OK"))
            self.assertEqual(harness.wait_for_window(title="Delete Empty Players"), "Delete Empty Players")
            self.assertTrue(harness.click("Delete Empty Players", "Delete Selected Players"))
            harness.check(self, removing.join(600), "case_musicxml.lua")


if __name__ == "__main__":
    unittest.main()
