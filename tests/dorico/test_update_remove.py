"""Updating, refusing and removing a chart in Dorico, on scratch copies of the fixture. Dorico's own Delete Flow
and Delete Empty Players dialogs are answered from here through UI Automation.

    python tests/dorico/test_update_remove.py
"""
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import harness  # noqa: E402

DOCS = harness.ROOT / "docs" / "plugin"


def layout(client):
    return harness.options(client, "kLayout", "layoutID", 0)


class UpdateAndRefuse(unittest.TestCase):
    def test_rerun_reuses_flow_and_players_then_a_renamed_flow_is_refused(self):
        with harness.scratch(self, "case_write.lua", args={"mode": "combined"}) as (client, first):
            again = harness.run_more(self, client, "case_write.lua", {"mode": "combined", "existing": True})
            a, b = first["facts"], again["facts"]
            self.assertEqual(b["found"], "ok")
            self.assertEqual(a["chartFlowId"], b["chartFlowId"], "the same chart flow")
            self.assertEqual(a["chartKeys"], b["chartKeys"], "the same chart players")
            for count in ("flowCount", "playerCount", "layoutCount"):
                self.assertEqual(a[count], b[count], count)
            self.assertEqual(b["restore"]["flowHeadingBehaviour"], "kAlwaysInsertHeadings", "kept from the first run")

            renamed = harness.run_more(self, client, "case_find.lua", {"renameTo": "Chart"})
            self.assertEqual(renamed["facts"]["status"], "invalid")
            self.assertIn('named "Chart"', renamed["facts"]["reason"])


class AddedPlayer(unittest.TestCase):
    def test_a_player_added_after_charting_does_not_block_an_update(self):
        with harness.scratch(self, "case_write.lua", args={"mode": "combined"}) as (client, first):
            added = harness.run_more(self, client, "case_addplayer.lua")["facts"]
            self.assertTrue(added["inChartFlow"], "Dorico put the new player into the chart flow")
            again = harness.run_more(self, client, "case_write.lua", {"mode": "combined", "existing": True})
            facts = again["facts"]
            self.assertEqual(facts["found"], "ok")
            self.assertIn(str(added["key"]), facts["musicKeys"].split(","), "the new player is music")
            self.assertEqual(facts["chartKeys"], first["facts"]["chartKeys"])
            self.assertEqual(layout(client).get("alwaysVisiblePlayers"), facts["musicIds"])


class SeparateThenCombinedThenRemove(unittest.TestCase):
    def test_update_leaves_no_old_notes_and_remove_follows_dorico_dialogs(self):
        with harness.scratch(self, "case_write.lua", args={"mode": "separate"}) as (client, first):
            combined = harness.run_more(self, client, "case_write.lua", {"mode": "combined", "existing": True})
            a, b = first["facts"], combined["facts"]
            self.assertEqual(a["chartFlowId"], b["chartFlowId"])
            self.assertEqual(set(a["chartKeys"].split(",")), set(b["chartKeys"].split(",")),
                             "every chart player kept, the extra ones as surplus")
            self.assertLess(len(b["slotKeys"].split(",")), len(a["slotKeys"].split(",")))
            harness.capture(client, DOCS / "update.png", height=1100)

            # cancelling Dorico's Delete Flow keeps the chart, and the options with it
            removing = harness.Background(lambda: harness.run_more(self, client, "case_remove.lua", expect_ok=False))
            self.assertEqual(harness.wait_for_window(title="Delete Flow"), "Delete Flow")
            self.assertTrue(harness.click("Delete Flow", "Cancel"))
            kept = harness.check(self, removing.join(300), "case_remove.lua")
            self.assertFalse(kept["facts"]["removed"])
            self.assertEqual(layout(client).get("flowHeadingBehaviour"), "kNoFlowHeadings")

            # confirming it removes the chart and puts the options back
            removing = harness.Background(lambda: harness.run_more(self, client, "case_remove.lua", expect_ok=False))
            self.assertEqual(harness.wait_for_window(title="Delete Flow"), "Delete Flow")
            harness.capture_window("Delete Flow", DOCS / "delete-flow.png")
            self.assertTrue(harness.click("Delete Flow", "OK"))
            self.assertEqual(harness.wait_for_window(title="Delete Empty Players"), "Delete Empty Players")
            harness.capture_window("Delete Empty Players", DOCS / "delete-empty-players.png")
            self.assertTrue(harness.click("Delete Empty Players", "Delete Selected Players"))
            gone = harness.check(self, removing.join(300), "case_remove.lua")["facts"]
            self.assertTrue(gone["removed"])
            self.assertEqual(gone["flowCount"], 1)
            self.assertEqual(gone["chartPlayersLeft"], "")
            self.assertEqual(gone["chartLayoutsLeft"], 0)
            options = layout(client)
            self.assertEqual(options.get("flowHeadingBehaviour"), "kAlwaysInsertHeadings")
            self.assertEqual(options.get("hideEmptyStavesPolicy"), "kNever")
            self.assertIn(options.get("staffLabelLayoutOptions.playersToShowPlayerName"), ("", None))


if __name__ == "__main__":
    unittest.main()
