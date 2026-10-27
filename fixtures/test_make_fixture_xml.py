import json
import os
import sys
import unittest
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import fixture_data  # noqa: E402
import make_fixture_xml  # noqa: E402


def measure(root, part_index, bar):
    part = root.findall("part")[part_index]
    return part.findall("measure")[bar - 1]


def pitches(m):
    out = []
    for note in m.findall("note"):
        p = note.find("pitch")
        if p is not None:
            alter = p.findtext("alter")
            out.append((p.findtext("step"), int(alter) if alter else 0, int(p.findtext("octave"))))
    return out


class MakeFixtureXmlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = ET.fromstring(make_fixture_xml.build_xml(fixture_data.FIXTURE))  # noqa: S314  # XML this test just built
        cls.heads = make_fixture_xml.build_heads(fixture_data.FIXTURE)

    def test_part_count(self):
        names = [sp.findtext("part-name") for sp in self.root.find("part-list").findall("score-part")]
        self.assertEqual(names, ["Handbells (A)", "Handbells (B)", "Organ"])

    def test_handbells_sound(self):
        sounds = [sp.find("score-instrument").findtext("instrument-sound")
                  for sp in self.root.find("part-list").findall("score-part")]
        self.assertEqual(sounds[:2], ["pitched-percussion.handbells"] * 2)
        self.assertEqual(sounds[2], "keyboard.organ")

    def test_enharmonics(self):
        ps = pitches(measure(self.root, 0, 2))
        self.assertIn(("G", 1, 4), ps)
        self.assertIn(("A", -1, 4), ps)

    def test_grace(self):
        graces = [n for n in measure(self.root, 0, 3).findall("note") if n.find("grace") is not None]
        self.assertEqual(len(graces), 1)
        self.assertEqual(graces[0].find("pitch").findtext("step"), "B")
        self.assertEqual(graces[0].find("pitch").findtext("octave"), "5")
        self.assertIsNone(graces[0].find("duration"))

    def test_chord(self):
        chords = [n for n in measure(self.root, 0, 2).findall("note") if n.find("chord") is not None]
        self.assertEqual(len(chords), 1)
        self.assertEqual(chords[0].find("pitch").findtext("step"), "E")

    def test_bar_durations_fill_4_4(self):
        for pi, part in enumerate(self.root.findall("part")):
            for bi, m in enumerate(part.findall("measure"), start=1):
                staves = {}
                for n in m.findall("note"):
                    if n.find("grace") is not None or n.find("chord") is not None:
                        continue
                    staff = n.findtext("staff")
                    staves[staff] = staves.get(staff, 0) + int(n.findtext("duration"))
                for staff, total in staves.items():
                    self.assertEqual(total, 16, f"part {pi} bar {bi} staff {staff}")

    def test_heads_json(self):
        a5 = [h for h in self.heads if h["player"] == "Handbells (A)" and h["bar"] == 5]
        self.assertEqual([h["colour"] for h in a5], ["#c80000", "#c80000", "#c80000", None])
        b2 = [h for h in self.heads if h["player"] == "Handbells (B)" and h["bar"] == 2]
        self.assertEqual(len(b2), 4)
        self.assertTrue(all(h["noteheadSet"] == "noteheadset.rectangular" for h in b2))
        grace = [h for h in self.heads if h["grace"]]
        self.assertEqual([(g["player"], g["bar"], g["pos"], g["name"]) for g in grace], [("Handbells (A)", 3, 0, "B")])

    def test_heads_keys_unique(self):
        keys = [(h["player"], h["bar"], h["pos"], h["name"], h["grace"]) for h in self.heads]
        self.assertEqual(len(keys), len(set(keys)))

    def test_expected_counts(self):
        self.assertEqual(fixture_data.EXPECTED["Handbells (A)"], {"bell": 18, "chime": 6, "x": 1})
        self.assertEqual(fixture_data.EXPECTED["Handbells (B)"], {"bell": 4, "smb": 4, "pf": 2, "wc": 2})
        self.assertEqual(fixture_data.EXPECTED["Organ"], {"bell": 21})

    def test_heads_json_is_serialisable(self):
        self.assertEqual(json.loads(json.dumps(self.heads)), self.heads)


if __name__ == "__main__":
    unittest.main()
