"""Content of the handbell test fixture.

Events per bar:
  ("n", [spellings...], quarters, kind)   a note, or a chord when several spellings are given
  ("g", spelling, kind)                   a grace note before the next event
  ("r", quarters)                         a rest
Spellings are written pitches ("Ab4", "G#4", "Bb2"). kind picks the notehead and colour from HEADS;
"x" is a notehead no instrument maps to (the unrecognised-notehead warning).
"""

HEADS = {
    "bell": ("noteheadset.default", None),
    "chime": ("noteheadset.diamondNoteheads", "#c80000"),
    "smb": ("noteheadset.rectangular", "#008000"),
    "pf": ("noteheadset.triangleDownNoteheads", "#e628fa"),
    "wc": ("noteheadset.triangleUpNoteheads", None),
    "x": ("noteheadset.Xnoteheads", None),
}

# MusicXML <notehead> values, as extra import evidence (heads.json is the authority).
MUSICXML_NOTEHEAD = {"bell": None, "chime": "diamond", "smb": "square", "pf": "inverted triangle", "wc": "triangle", "x": "x"}

# Notes whose colour is deliberately left off although their kind has one: (player, bar, pos, name).
# The A5 chime G4 stays black so the majority-colour rule has something to ignore.
UNCOLOURED = {("Handbells (A)", 5, 3, "G")}

HANDBELLS = "pitched-percussion.handbells"
ORGAN = "keyboard.organ"

FIXTURE = {
    "title": "Handbells Chart Fixture",
    "key_fifths": -1,
    "time": (4, 4),
    "players": [
        {
            "name": "Handbells (A)",
            "instrument": HANDBELLS,
            "staves": 2,
            "bars": [
                [("n", ["C4"], 1, "bell"), ("n", ["D4"], 1, "bell"), ("n", ["E4"], 1, "bell"), ("n", ["F4"], 1, "bell")],
                [("n", ["G#4"], 1, "bell"), ("n", ["Ab4"], 1, "bell"), ("n", ["Bb4"], 1, "bell"), ("n", ["C5", "E5"], 1, "bell")],
                [("g", "B5", "bell"), ("n", ["C6", "G6"], 2, "bell"), ("n", ["D7"], 1, "bell"), ("n", ["G2"], 1, "bell")],
                [("n", ["C2"], 1, "bell"), ("n", ["B1"], 1, "bell"), ("n", ["F#3"], 1, "bell"), ("n", ["Gb3"], 1, "bell")],
                [("n", ["C4"], 1, "chime"), ("n", ["D4"], 1, "chime"), ("n", ["F#4"], 1, "chime"), ("n", ["G4"], 1, "chime")],
                [("n", ["A4"], 2, "chime"), ("n", ["B4"], 2, "chime")],
                [("n", ["E4"], 4, "x")],
            ],
        },
        {
            "name": "Handbells (B)",
            "instrument": HANDBELLS,
            "staves": 2,
            "bars": [
                [("n", ["D4"], 1, "bell"), ("n", ["F4"], 1, "bell"), ("n", ["A4"], 1, "bell"), ("n", ["C5"], 1, "bell")],
                [("n", ["C5"], 1, "smb"), ("n", ["D5"], 1, "smb"), ("n", ["F#5"], 1, "smb"), ("n", ["G5"], 1, "smb")],
                [("n", ["E4"], 2, "pf"), ("n", ["G4"], 2, "pf")],
                [("n", ["A3"], 2, "wc"), ("n", ["C4"], 2, "wc")],
                [("r", 4)],
                [("r", 4)],
                [("r", 4)],
            ],
        },
        {
            "name": "Organ",
            "instrument": ORGAN,
            "staves": 2,
            "bars": [[("n", ["F3", "A3", "C4"], 4, "bell")] for _ in range(7)],
        },
    ],
}


def _expected(fixture):
    out = {}
    for player in fixture["players"]:
        counts = {}
        for bar in player["bars"]:
            for ev in bar:
                if ev[0] == "n":
                    counts[ev[3]] = counts.get(ev[3], 0) + len(ev[1])
                elif ev[0] == "g":
                    counts[ev[2]] = counts.get(ev[2], 0) + 1
        out[player["name"]] = counts
    return out


# Note events per player and kind, grace notes and every chord member included.
EXPECTED = _expected(FIXTURE)
