"""Reading players, notes, noteheads and colours in Dorico, on scratch copies.

    python tests/dorico/test_read.py
"""
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import inputs  # noqa: E402
import harness  # noqa: E402
from test_guards import FIXTURE, run_case  # noqa: E402

# What the fixture's music carries (fixtures/fixture_data.py).
FIXTURE_HISTOGRAM = {
    "noteheadset.default|": 43,
    "noteheadset.Xnoteheads|": 1,
    "noteheadset.diamondNoteheads|": 1,
    "noteheadset.diamondNoteheads|#c80000": 5,
    "noteheadset.rectangular|#008000": 4,
    "noteheadset.triangleDownNoteheads|#e628fa": 2,
    "noteheadset.triangleUpNoteheads|": 2,
}
FIXTURE_PLAYERS = ["Handbells (A)", "Handbells (B)", "Organ"]


class ReadTests(unittest.TestCase):
    def test_fixture_reads_directly(self):
        run_case(self, "case_read.lua", FIXTURE, {"expect": {
            "players": FIXTURE_PLAYERS, "records": 58, "pastedFlows": 0, "histogram": FIXTURE_HISTOGRAM}})

    def test_fixture_paste_route_matches_direct(self):
        run_case(self, "case_read.lua", FIXTURE, {"forcePaste": True, "expect": {
            "players": FIXTURE_PLAYERS, "records": 58, "pastedFlows": 1, "histogram": FIXTURE_HISTOGRAM}})

    def paste_matches_direct(self, args):
        # The copied range starts on the first staff with a note or rest. Pasted any higher in the scratch flow,
        # every staff's notes would be credited to the player above, and case_read would find notes unread.
        with harness.scratch(self, "case_tacet.lua", args=args) as (client, _):
            direct = harness.run_more(self, client, "case_read.lua")["facts"]
            pasted = harness.run_more(self, client, "case_read.lua", {"forcePaste": True})["facts"]
            self.assertEqual((direct["pastedFlows"], pasted["pastedFlows"]), (0, 1))
            self.assertEqual(pasted["byInstrument"], direct["byInstrument"])

    def test_paste_route_when_the_first_player_is_tacet(self):
        self.paste_matches_direct({})

    def test_paste_route_when_the_first_treble_staff_is_empty(self):
        self.paste_matches_direct({"topOnly": True})

    def test_a_notehead_set_by_command_is_marked_unreadable(self):
        # Dorico's own command stores the set in a form Lua reads as "", like the default set. The note still lists
        # the property, so the read flags it for a MusicXML export, on both routes.
        with harness.scratch(self, "case_heads.lua", args={"sets": ["noteheadset.diamondNoteheads"]}) as (client, result):
            self.assertEqual(result["facts"]["redone"], 6, "the fixture's six diamond notes")
            for args in ({}, {"forcePaste": True}):
                facts = harness.run_more(self, client, "case_read.lua", args)["facts"]
                self.assertEqual(facts["headUnreadable"], 6, args)

    def test_a_colour_set_by_command_is_marked_unreadable(self):
        # It reads back as "", like no colour. The note still lists the property, so the read can tell the two apart
        # and keep the note out of the colour the dialog suggests.
        with harness.scratch(self, "case_colour.lua") as (client, _):
            for args in ({}, {"forcePaste": True}):
                facts = harness.run_more(self, client, "case_read.lua", args)["facts"]
                self.assertEqual(facts["colourUnreadable"], 1, args)
                self.assertEqual(facts["histogram"], FIXTURE_HISTOGRAM, "and its head and colour read as before")

    def test_smith_reads_through_the_paste_route_and_leaves_no_trace(self):
        result = run_case(self, "case_read.lua", inputs.ensure("smith"), timeout=600)
        facts = result["facts"]
        self.assertGreater(facts["pastedFlows"], 0)
        # The case checks that no note is unread and the music is unchanged. Unisons between voices of one staff
        # merge in the copy, so there may be fewer records than dumped notes, never more.
        dumped = sum(int(part.split("=")[1].split("n/")[0]) for part in facts["summary"].split(","))
        self.assertLessEqual(facts["records"], dumped)
        self.assertGreater(facts["records"], dumped * 0.9)

    def test_a_user_edit_before_the_read_survives_and_still_undoes(self):
        # The copy is taken away with Edit.Undo: the user's own last edit, made before the run, must outlive it and
        # still be the next thing Edit.Undo takes back.
        with harness.scratch(self, "case_titles.lua") as (client, before):
            original = before["facts"]["titles"]["1"]
            # an edit of the user's, made before the run as its own undo step (a script run, like a menu action;
            # the same rename sent through the Remote API is refused with kError)
            harness.run_more(self, client, "case_titles.lua", {"renameFirstFlow": "User Edit"})
            harness.run_more(self, client, "case_read.lua", {"forcePaste": True})
            after = harness.run_more(self, client, "case_titles.lua")["facts"]["titles"]
            self.assertEqual(after["1"], "User Edit", "the user's edit survived the read")
            client.command("Edit.Undo")
            undone = harness.run_more(self, client, "case_titles.lua")["facts"]["titles"]
            self.assertEqual(undone["1"], original, "and is still the user's to undo")

    def test_a_user_edit_survives_a_read_of_several_flows(self):
        # A second Edit.Undo in one run takes back the user's previous action too (spike/29_undo_experiments.py E9),
        # so several flows read through the copy must be taken away with a single undo.
        with harness.scratch(self, "case_titles.lua") as (client, before):
            original = before["facts"]["titles"]["1"]
            harness.run_more(self, client, "case_titles.lua", {"secondFlow": True})
            harness.run_more(self, client, "case_titles.lua", {"renameFirstFlow": "User Edit"})
            read = harness.run_more(self, client, "case_read.lua", {"forcePaste": True})
            self.assertEqual(read["facts"]["pastedFlows"], 2)
            after = harness.run_more(self, client, "case_titles.lua")["facts"]["titles"]
            self.assertEqual(after["1"], "User Edit", "the user's edit survived the read")
            client.command("Edit.Undo")
            undone = harness.run_more(self, client, "case_titles.lua")["facts"]["titles"]
            self.assertEqual(undone["1"], original, "and is still the user's to undo")

    def test_liszt_merged_unisons_are_not_lost(self):
        result = run_case(self, "case_read.lua", inputs.ensure("liszt"), timeout=600)
        self.assertEqual(result["facts"]["pastedFlows"], 1)


if __name__ == "__main__":
    unittest.main()
