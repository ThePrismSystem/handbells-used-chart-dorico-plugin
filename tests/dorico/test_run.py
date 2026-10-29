"""The whole run in Dorico: main.run with a scripted dialog on scratch copies, and once through the Script menu's
own entry file with the real dialog.

    python tests/dorico/test_run.py
"""
import os
import shutil
import sys
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parents[1] / "tools"))
sys.path.insert(0, str(HERE.parents[1] / "tests" / "dialog"))
import harness  # noqa: E402
import install  # noqa: E402
from test_windows_dialog import RESULTS, TITLE, click, wait_window, window_exists  # noqa: E402

DOCS = harness.ROOT / "docs" / "plugin"


class ScriptedRuns(unittest.TestCase):
    def test_first_run_draws_and_a_second_replaces(self):
        args = {"answer": "draw", "expect": "drawn", "freshSettings": True}
        with harness.scratch(self, "case_run.lua", args=args) as (client, first):
            harness.capture(client, DOCS / "run.png")
            harness.run_more(self, client, "case_run.lua", {"answer": "draw", "expect": "replaced"})

    def test_same_head_twice_is_refused_before_saving(self):
        with harness.scratch(self, "case_run.lua", args={"answer": "same-head", "expect": "sameHead"}):
            pass

    def test_remove_without_a_chart_says_so(self):
        with harness.scratch(self, "case_run.lua", args={"answer": "remove", "expect": "noChart"}):
            pass

    def test_a_run_from_engrave_mode_still_draws(self):
        with harness.scratch(self, "case_run.lua", args={"answer": "draw", "expect": "drawn", "freshSettings": True,
                                                         "startMode": "kEngraveMode"}):
            pass

    def test_a_run_with_a_part_on_screen_asks_for_the_full_score(self):
        args = {"answer": "draw", "expect": "notFull", "startLayout": 1}
        with harness.scratch(self, "case_run.lua", args=args) as (client, result):
            if result["facts"].get("skip"):
                self.skipTest(result["facts"]["skip"])

    def test_a_save_that_does_not_happen_stops_the_run(self):
        with harness.scratch(self, "case_run.lua", args={"answer": "draw", "expect": "saveFailed", "blockSave": True}):
            pass

    def test_organ_written_as_handbells_charts_its_sounding_notes(self):
        # the fixture's Organ plays F3 A3 C4 (sounding = written): read as a Handbells instrument, those are its bells
        with harness.scratch(self, "case_run.lua", args={"answer": "organ", "expect": "organ",
                                                         "spellings": ["F3", "A3", "C4"]}):
            pass

    def test_organ_set_at_pitch_charts_an_octave_up(self):
        with harness.scratch(self, "case_run.lua", args={"answer": "organ-at-pitch", "expect": "organ",
                                                         "spellings": ["F4", "A4", "C5"]}):
            pass

    def test_one_undo_takes_back_only_the_chart(self):
        # The read undoes nothing any more, so a run is an undo step of its own: one Edit > Undo takes the chart away
        # and leaves the user's edit before it. (With the paste route's undo, the chart joined that edit's step.)
        with harness.scratch(self, "case_titles.lua") as (client, _):
            harness.run_more(self, client, "case_titles.lua", {"renameFirstFlow": "User Edit"})
            harness.run_more(self, client, "case_run.lua", {"answer": "draw", "expect": "drawn", "freshSettings": True})
            drawn = harness.run_more(self, client, "case_titles.lua")["facts"]["titles"]
            self.assertEqual(drawn.get("2"), "User Edit", "the chart's flow comes first")
            client.command("Edit.Undo")
            titles = harness.run_more(self, client, "case_titles.lua")["facts"]["titles"]
            self.assertEqual(titles["all"], ["User Edit"], "the chart has gone and the user's edit stays")

    def test_cancel_changes_nothing(self):
        with harness.scratch(self, "case_run.lua", args={"answer": "cancel", "expect": "cancelled", "freshSettings": True}):
            pass


class RealDialog(unittest.TestCase):
    """Installs the plug-in where Dorico looks for it and runs its menu entry on a scratch copy. Whatever was
    installed or remembered before is put back afterwards."""

    def setUp(self):
        self.target = install.default_target()
        self.data = Path(os.environ["APPDATA"]) / "Handbells Used Chart"
        self.backup = Path(harness.run_lua.RUN_DIR) / "e2e-backup"
        shutil.rmtree(self.backup, ignore_errors=True)
        self.backup.mkdir(parents=True)
        self.had_install = (self.target / install.ENTRY).exists()
        if self.had_install:
            shutil.copy2(self.target / install.ENTRY, self.backup / install.ENTRY)
            shutil.copytree(self.target / install.FOLDER, self.backup / install.FOLDER)
        self.had_data = self.data.exists()
        if self.had_data:
            shutil.copytree(self.data, self.backup / "data")
        self.addCleanup(self.restore)
        self.addCleanup(self.dismiss)
        install.install(self.target)

    def dismiss(self):
        # Never leave a plug-in window open: Dorico waits on it, and every later test would time out.
        for title, button in ((TITLE, "Cancel"), (RESULTS, "OK")):
            for _ in range(3):
                if not window_exists(title):
                    break
                click(title, button)
                time.sleep(2)

    def restore(self):
        install.uninstall(self.target)
        if self.had_install:
            shutil.copy2(self.backup / install.ENTRY, self.target / install.ENTRY)
            shutil.copytree(self.backup / install.FOLDER, self.target / install.FOLDER)
        shutil.rmtree(self.data, ignore_errors=True)
        if self.had_data:
            shutil.copytree(self.backup / "data", self.data)

    def test_the_menu_entry_draws_a_chart_through_the_real_dialog(self):
        with harness.scratch(self, "case_find.lua") as (client, before):
            try:
                self.assertEqual(before["facts"]["status"], "none")
                entry = harness.run_lua.fwd(self.target / install.ENTRY)
                # sent without waiting: Dorico may answer only once the script, which waits on the dialog, has ended
                client.send({"message": "command", "command": f"Script.RunScript?ScriptPath={entry}&ShowConsole=false"})
                self.assertTrue(wait_window(TITLE, timeout=120), "the dialog did not open")
                time.sleep(1)
                self.assertTrue(click(TITLE, "OK"))
                self.assertTrue(wait_window(RESULTS, timeout=300), "no results window")
                time.sleep(1)
                self.assertTrue(click(RESULTS, "OK"))
                time.sleep(2)
                after = harness.run_more(self, client, "case_find.lua")
                self.assertEqual(after["facts"]["status"], "ok")
                log = (self.data / "run.log").read_text(encoding="utf-8", errors="replace")
                self.assertIn("message info", log)
            finally:
                # Before the copy is closed: closing it lists Dorico's windows, which waits on Dorico, which waits
                # on any plug-in window still open (a failure here once hung the suite for 40 minutes).
                self.dismiss()


if __name__ == "__main__":
    unittest.main()
