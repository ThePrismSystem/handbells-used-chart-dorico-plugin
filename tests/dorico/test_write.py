"""Drawing a new chart in Dorico, on scratch copies of the fixture.

    python tests/dorico/test_write.py
"""
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import harness  # noqa: E402
import inputs  # noqa: E402

DOCS = harness.ROOT / "docs" / "plugin"
IMAGES = harness.ROOT / "images"


class WriteTests(unittest.TestCase):
    def check_options(self, client, facts):
        layout = harness.options(client, "kLayout", "layoutID", 0)
        # one music flow: no headings, so its title is not printed twice
        self.assertEqual(layout.get("flowHeadingBehaviour"), "kNoFlowHeadings")
        self.assertEqual(layout.get("hideEmptyStavesPolicy"), "kAllSystems")
        self.assertEqual(layout.get("alwaysVisiblePlayers"), facts["musicIds"])
        self.assertEqual(layout.get("staffLabelLayoutOptions.playersToShowPlayerName"), facts["chartIds"])
        chart = harness.options(client, "kNotation", "flowID", facts["chartFlowId"])
        music = harness.options(client, "kNotation", "flowID", 0)
        self.assertEqual((chart.get("barlineOptions.finalBarlineType"), chart.get("barlineOptions.defaultBarlineType")),
                         ("kNone", "kNone"))
        self.assertEqual((music.get("barlineOptions.finalBarlineType"), music.get("barlineOptions.defaultBarlineType")),
                         ("kFinal", "kNormal"))

    def test_combined_chart_is_drawn(self):
        with harness.scratch(self, "case_write.lua", args={"mode": "combined"}) as (client, result):
            facts = result["facts"]
            self.assertEqual(facts["musicKeys"], "0,1,2")
            self.assertEqual(facts["restore"]["flowHeadingBehaviour"], "kAlwaysInsertHeadings")
            self.check_options(client, facts)
            harness.capture(client, IMAGES / "combined.png")

    def test_separate_chart_is_drawn(self):
        with harness.scratch(self, "case_write.lua", args={"mode": "separate"}) as (client, result):
            labels = result["facts"]["labels"]
            self.assertTrue(any(label.startswith("Handbells (A) - ") for label in labels), labels)
            self.assertTrue(any(label.startswith("Handbells (B) - ") for label in labels), labels)
            self.check_options(client, result["facts"])
            harness.capture(client, DOCS / "separate.png", height=1500)


class RealScores(unittest.TestCase):
    """The example projects hold lyrics, slurs, many flows and several voices per staff; every note is read as a
    handbell with the plain notehead, which is enough to draw a chart and check the music is untouched."""

    def test_smith_is_charted_without_touching_the_music(self):
        # Smith's player ids are not its instrument ids: the layout options must name the real player ids
        with harness.scratch(self, "case_write.lua", open_file=inputs.ensure("smith"), args={"mode": "combined"},
                             timeout=900) as (client, result):
            facts = result["facts"]
            self.assertNotEqual(facts["musicIds"], facts["musicKeys"], "this project's ids differ from its keys")
            layout = harness.options(client, "kLayout", "layoutID", 0)
            self.assertEqual(layout.get("alwaysVisiblePlayers"), facts["musicIds"])
            self.assertEqual(layout.get("staffLabelLayoutOptions.playersToShowPlayerName"), facts["chartIds"])
            # its export lists flow titles without flow numbers: the chart must still be found for an update
            again = harness.run_more(self, client, "case_write.lua", {"mode": "combined", "existing": True}, timeout=900)
            self.assertEqual(again["facts"]["found"], "ok")
            self.assertEqual(again["facts"]["chartFlowId"], facts["chartFlowId"])

    def test_liszt_is_charted_without_touching_the_music(self):
        with harness.scratch(self, "case_write.lua", open_file=inputs.ensure("liszt"), args={"mode": "combined"},
                             timeout=900):
            pass


if __name__ == "__main__":
    unittest.main()
