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
FIXTURE_HEADS = {
    "noteheadset.default": 43, "noteheadset.Xnoteheads": 1, "noteheadset.diamondNoteheads": 6,
    "noteheadset.rectangular": 4, "noteheadset.triangleDownNoteheads": 2, "noteheadset.triangleUpNoteheads": 2,
}


def dumped_notes(summary):
    """The note count of every flow, from case_read's "<id>=<notes>n/<players>p,..." summary."""
    return sum(int(part.split("=")[1].split("n/")[0]) for part in summary.split(","))


class ReadTests(unittest.TestCase):
    def test_fixture_reads(self):
        run_case(self, "case_read.lua", FIXTURE, {"expect": {
            "players": FIXTURE_PLAYERS, "records": 58, "histogram": FIXTURE_HISTOGRAM}})

    def test_saved_copy_reads_heads_set_by_command(self):
        # Every one of the fixture's changed heads given again by Dorico's own command, which Lua can't read: the
        # saved copy has them all, each in the note's own block instance.
        with harness.scratch(self, "case_heads.lua") as (client, result):
            self.assertEqual(result["facts"]["redone"], 15, "every changed head")
            facts = harness.run_more(self, client, "case_savedcopy.lua")["facts"]
            self.assertEqual(facts["heads"], FIXTURE_HEADS)

    def test_heads_set_by_command_are_read(self):
        with harness.scratch(self, "case_heads.lua") as (client, _):
            harness.run_more(self, client, "case_read.lua", {"expect": {"records": 58, "histogram": FIXTURE_HISTOGRAM}})

    def test_a_colour_set_by_command_is_read(self):
        # case_colour reds the first note (a plain C5) the way the Properties panel does
        with harness.scratch(self, "case_colour.lua") as (client, _):
            want = dict(FIXTURE_HISTOGRAM)
            want["noteheadset.default|"] -= 1
            want["noteheadset.default|#ff0000"] = 1
            harness.run_more(self, client, "case_read.lua", {"expect": {"histogram": want}})

    def test_a_colour_set_in_a_part_stays_in_the_part(self):
        # With a part on screen, the Properties panel's local scope sets a colour for that layout only. A read from
        # the part sees it, which shows it was set; a read from the full score, as a run makes, doesn't.
        with harness.scratch(self, "case_layouts.lua") as (client, result):
            facts = result["facts"]
            score, part, full = facts["scratchScoreID"], facts["firstPartLayout"], facts["fullLayout"]

            def show(layout):
                view = client.status().get("activeViewContainerID")
                client.command(f"Window.SwitchToLayout?OpenScoreID={score}&ScoreLayoutViewContainerID={view}"
                               f"&LayoutID={layout}")
                client.settle()

            show(part)
            harness.run_more(self, client, "case_colour.lua")
            in_part = harness.run_more(self, client, "case_read.lua")["facts"]
            self.assertEqual(in_part["layoutId"], part, "read with the part on screen")
            self.assertEqual(in_part["histogram"].get("noteheadset.default|#ff0000"), 1, "the colour was set")
            show(full)
            in_full = harness.run_more(self, client, "case_read.lua", {"expect": {"histogram": FIXTURE_HISTOGRAM}})
            self.assertEqual(in_full["facts"]["layoutId"], full)

    def test_smith_reads_every_note_and_leaves_no_trace(self):
        # The case checks that the music and its flows are as they were. Every dumped note is a record, unisons
        # between voices of one staff included.
        facts = run_case(self, "case_read.lua", inputs.ensure("smith"), timeout=600)["facts"]
        self.assertEqual(facts["records"], dumped_notes(facts["summary"]))

    def test_liszt_reads_every_note(self):
        # the paste route this replaced merged 12 unisons between voices
        facts = run_case(self, "case_read.lua", inputs.ensure("liszt"), timeout=600)["facts"]
        self.assertEqual(facts["records"], 1906)

    def test_the_read_leaves_the_users_edit_and_its_undo_alone(self):
        with harness.scratch(self, "case_titles.lua") as (client, before):
            original = before["facts"]["titles"]["1"]
            # an edit of the user's, made before the run as its own undo step (a script run, like a menu action;
            # the same rename sent through the Remote API is refused with kError)
            harness.run_more(self, client, "case_titles.lua", {"renameFirstFlow": "User Edit"})
            harness.run_more(self, client, "case_read.lua")
            after = harness.run_more(self, client, "case_titles.lua")["facts"]["titles"]
            self.assertEqual(after["1"], "User Edit", "the user's edit survived the read")
            client.command("Edit.Undo")
            undone = harness.run_more(self, client, "case_titles.lua")["facts"]["titles"]
            self.assertEqual(undone["1"], original, "the read added no undo step of its own")


if __name__ == "__main__":
    unittest.main()
