"""Write the handbell fixture as MusicXML plus heads.json (the noteheads and colours to apply after import).

    python fixtures/make_fixture_xml.py   ->  fixtures/build/handbells-fixture.musicxml, fixtures/build/heads.json
"""
import json
import os
import sys
from pathlib import Path
from xml.sax.saxutils import escape

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fixture_data  # noqa: E402

DIVISIONS = 4  # per quarter note
TYPES = {1: "quarter", 2: "half", 4: "whole"}
BUILD = Path(__file__).resolve().parent / "build"


def parse_spelling(s):
    """'Ab4' -> ('A', -1, 4); 'F#3' -> ('F', 1, 3)."""
    step, rest = s[0], s[1:]
    alter = 0
    while rest and rest[0] in "#b":
        alter += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return step, alter, int(rest)


def midi(s):
    step, alter, octave = parse_spelling(s)
    return 12 * (octave + 1) + {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}[step] + alter


def note_name(s):
    step, alter, _ = parse_spelling(s)
    return step + ("#" * alter if alter > 0 else "b" * -alter)


def staff_of(spellings):
    """Treble for C4 and above, bass below; a chord goes where its lowest note goes."""
    return 1 if min(midi(s) for s in spellings) >= midi("C4") else 2


def _note_xml(spelling, quarters, staff, kind, chord=False, grace=False, colour=None):
    step, alter, octave = parse_spelling(spelling)
    attrs = f' color="{colour.upper()}"' if colour else ""
    parts = [f"<note{attrs}>"]
    if grace:
        parts.append('<grace slash="no"/>')
    if chord:
        parts.append("<chord/>")
    parts.append(f"<pitch><step>{step}</step>" + (f"<alter>{alter}</alter>" if alter else "") + f"<octave>{octave}</octave></pitch>")
    if not grace:
        parts.append(f"<duration>{quarters * DIVISIONS}</duration>")
    parts.append(f"<voice>{1 if staff == 1 else 5}</voice>")
    parts.append(f"<type>{TYPES[quarters] if not grace else 'eighth'}</type>")
    head = fixture_data.MUSICXML_NOTEHEAD[kind]
    if head:
        parts.append(f"<notehead>{head}</notehead>")
    parts.append(f"<staff>{staff}</staff></note>")
    return "".join(parts)


def _rest_xml(quarters, staff, whole_bar=False):
    rest = '<rest measure="yes"/>' if whole_bar else "<rest/>"
    type_ = "" if whole_bar else f"<type>{TYPES[quarters]}</type>"
    return f"<note>{rest}<duration>{quarters * DIVISIONS}</duration><voice>{1 if staff == 1 else 5}</voice>{type_}<staff>{staff}</staff></note>"


def _colour_for(player, bar, pos, spelling, kind):
    colour = fixture_data.HEADS[kind][1]
    if (player, bar, pos, note_name(spelling)) in fixture_data.UNCOLOURED:
        return None
    return colour


def _bar_xml(player, bar_no, events, first, fixture):
    out = [f'<measure number="{bar_no}">']
    if first:
        beats, beat_type = fixture["time"]
        transpose = ("<transpose><diatonic>0</diatonic><chromatic>0</chromatic><octave-change>1</octave-change></transpose>"
                     if player["instrument"] == fixture_data.HANDBELLS else "")
        out.append(f"<attributes><divisions>{DIVISIONS}</divisions><key><fifths>{fixture['key_fifths']}</fifths></key>"
                   f"<time><beats>{beats}</beats><beat-type>{beat_type}</beat-type></time><staves>2</staves>"
                   f"<clef number=\"1\"><sign>G</sign><line>2</line></clef><clef number=\"2\"><sign>F</sign><line>4</line></clef>"
                   f"{transpose}</attributes>")
    if all(ev[0] == "r" for ev in events):
        out.append(_rest_xml(4, 1, whole_bar=True))
        out.append(f"<backup><duration>{4 * DIVISIONS}</duration></backup>")
        out.append(_rest_xml(4, 2, whole_bar=True))
        out.append("</measure>")
        return "".join(out)
    for staff in (1, 2):
        if staff == 2:
            out.append(f"<backup><duration>{4 * DIVISIONS}</duration></backup>")
        pos = 0
        pending_grace = None
        for ev in events:
            if ev[0] == "g":
                pending_grace = ev
                continue
            if ev[0] == "r":
                out.append(_rest_xml(ev[1], staff))
                pos += ev[1]
                continue
            _, spellings, quarters, kind = ev
            if staff_of(spellings) == staff:
                if pending_grace:
                    g = pending_grace[1]
                    out.append(_note_xml(g, 0, staff, pending_grace[2], grace=True,
                                         colour=_colour_for(player["name"], bar_no, pos, g, pending_grace[2])))
                for i, s in enumerate(spellings):
                    out.append(_note_xml(s, quarters, staff, kind, chord=i > 0,
                                         colour=_colour_for(player["name"], bar_no, pos, s, kind)))
            else:
                out.append(_rest_xml(quarters, staff))
            pending_grace = None
            pos += quarters
    out.append("</measure>")
    return "".join(out)


def build_xml(fixture):
    part_list = []
    parts = []
    for i, player in enumerate(fixture["players"], start=1):
        pid = f"P{i}"
        part_list.append(
            f'<score-part id="{pid}"><part-name>{escape(player["name"])}</part-name>'
            f'<score-instrument id="{pid}-I1"><instrument-name>{escape(player["name"])}</instrument-name>'
            f'<instrument-sound>{player["instrument"]}</instrument-sound></score-instrument></score-part>'
        )
        bars = [_bar_xml(player, n, events, n == 1, fixture) for n, events in enumerate(player["bars"], start=1)]
        parts.append(f'<part id="{pid}">' + "".join(bars) + "</part>")
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">\n'
        '<score-partwise version="4.0">'
        f'<work><work-title>{escape(fixture["title"])}</work-title></work>'
        '<identification><creator type="composer">Fixture Generator</creator></identification>'
        f'<part-list>{"".join(part_list)}</part-list>{"".join(parts)}</score-partwise>\n'
    )


def build_heads(fixture):
    """One entry per note event (grace notes and chord members included), in bar order."""
    heads = []
    for player in fixture["players"]:
        for bar_no, events in enumerate(player["bars"], start=1):
            pos = 0
            index = 0
            for ev in events:
                if ev[0] == "r":
                    pos += ev[1]
                    continue
                if ev[0] == "g":
                    spellings, kind, grace = [ev[1]], ev[2], True
                else:
                    spellings, kind, grace = ev[1], ev[3], False
                for s in spellings:
                    index += 1
                    heads.append({
                        "player": player["name"], "bar": bar_no, "pos": pos, "name": note_name(s),
                        "written": s, "grace": grace, "index": index, "kind": kind,
                        "noteheadSet": fixture_data.HEADS[kind][0],
                        "colour": _colour_for(player["name"], bar_no, pos, s, kind),
                    })
                if not grace:
                    pos += ev[2]
    return heads


def main():
    BUILD.mkdir(exist_ok=True)
    (BUILD / "handbells-fixture.musicxml").write_text(build_xml(fixture_data.FIXTURE), encoding="utf-8")
    (BUILD / "heads.json").write_text(json.dumps(build_heads(fixture_data.FIXTURE), indent=1), encoding="utf-8")
    print(f"wrote {BUILD / 'handbells-fixture.musicxml'} and heads.json")


if __name__ == "__main__":
    main()
