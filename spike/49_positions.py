"""Do the dumps' note positions agree with a MusicXML export's?

    python spike/49_positions.py PROJECT.dorico

On a scratch copy: spike/49_positions.lua lists every dumped note (player, position, sounding spelling, grace);
then spike/48_notehead_survey.lua's export step opens Dorico's MusicXML export and this presses OK. Each flow's
full-score file is read with the position rules the plug-in's reader will use (divisions, duration, backup,
forward, chord; grace notes at the next note's onset; tie stops and cue notes skipped; sounding pitch from
<transpose> per staff), and its notes are compared with the dump's, as multisets of (position, pitch, diatonic,
grace), per flow and per part. A project that asks a question on opening waits up to 10 minutes for someone to
answer it. Output: %TEMP%\\hbuc-run\\49\\<project>.json. The copy is closed unsaved and the export deleted.
"""
import json
import re
import shutil
import sys
import time
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tests" / "dorico"))
import harness  # noqa: E402
import dws  # noqa: E402
import run_lua  # noqa: E402

PROBE = REPO / "spike" / "49_positions.lua"
EXPORT = REPO / "spike" / "48_notehead_survey.lua"
OUT = run_lua.RUN_DIR / "49"
STEP = {"C": 0, "D": 1, "E": 2, "F": 3, "G": 4, "A": 5, "B": 6}
SEMI = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
ALTER = {"": 0, "#": 1, "x": 2, "##": 2, "b": -1, "bb": -2}


def key(pos, pitch, diatonic, grace):
    return f"{pos:.3f}|{pitch}|{diatonic}|{grace}"


def from_spelling(s):
    m = re.match(r"^([A-G])([#bx]*)(-?\d+)$", s)
    step, acc, octave = m.group(1), m.group(2), int(m.group(3))
    return (octave + 1) * 12 + SEMI[step] + ALTER[acc], octave * 7 + STEP[step]


def read_musicxml(path):
    root = ET.parse(path).getroot()
    names = {sp.get("id"): sp.findtext("part-name") for sp in root.iter("score-part")}
    parts = {}
    for part in root.findall("part"):
        notes, divisions, transpose = [], 1, {}
        start = 0.0
        for measure in part.findall("measure"):
            cursor, longest, onset = start, start, start
            for el in measure:
                if el.tag == "attributes":
                    divisions = int(el.findtext("divisions") or divisions)
                    for t in el.findall("transpose"):
                        transpose[t.get("number")] = (int(t.findtext("chromatic") or 0), int(t.findtext("diatonic") or 0),
                                                      int(t.findtext("octave-change") or 0))
                elif el.tag == "note":
                    length = int(el.findtext("duration") or 0) / divisions
                    grace = el.find("grace") is not None
                    if el.find("chord") is None:
                        onset = cursor
                    pitch = el.find("pitch")
                    tie_stop = any(t.get("type") == "stop" for t in el.findall("tie"))
                    if pitch is not None and el.find("cue") is None and not tie_stop:
                        step, octave = pitch.findtext("step"), int(pitch.findtext("octave"))
                        alter = int(float(pitch.findtext("alter") or 0))
                        chromatic, diatonic, octaves = transpose.get(el.findtext("staff") or "1", transpose.get(None, (0, 0, 0)))
                        midi = (octave + 1) * 12 + SEMI[step] + alter + chromatic + 12 * octaves
                        dia = octave * 7 + STEP[step] + diatonic + 7 * octaves
                        notes.append(key(onset, midi, dia, grace))
                    if el.find("chord") is None and not grace:
                        cursor += length
                elif el.tag == "backup":
                    cursor -= int(el.findtext("duration")) / divisions
                elif el.tag == "forward":
                    cursor += int(el.findtext("duration")) / divisions
                longest = max(longest, cursor)
            start = longest
        parts[names.get(part.get("id"), part.get("id"))] = notes
    return parts


def main():
    source = Path(sys.argv[1])
    OUT.mkdir(parents=True, exist_ok=True)
    # An earlier spike's export: Dorico would ask about overwriting each file.
    for old in run_lua.RUN_DIR.glob("Flows from *"):
        shutil.rmtree(old)
    before = set()
    client = dws.DoricoClient()
    client.connect()
    verified, sid = False, None
    try:
        try:
            code, result, sid = run_lua.run(PROBE, open_file=source, keep_open=True, client=client, timeout=900)
        except TimeoutError:
            print("waiting for the copy to open (answer Dorico's question if it asks one)", flush=True)
            deadline = time.time() + 600
            while time.time() < deadline and not run_lua.scratch_open():
                time.sleep(2)
            client.settle()
            code, result, sid = run_lua.run(PROBE, on_active=True, client=client, timeout=900,
                                            extra_args={"expectScratch": {"path": run_lua.fwd(harness.SCRATCH)}})
        facts = (result or {}).get("facts") or {}
        verified = bool(facts.get("scratchVerified"))
        print("probe: exit", code, "error", (result or {}).get("error"), flush=True)
        if not verified:
            return
        sid = facts["scratchScoreID"]
        extra = {"step": "export", "expectScratch": {"path": run_lua.fwd(harness.SCRATCH)}}
        run = harness.Background(lambda: run_lua.run(EXPORT, on_active=True, client=client, timeout=900, extra_args=extra))
        if harness.wait_for_window(timeout=600, title="Export MusicXML") == "Export MusicXML":
            time.sleep(1)
            print("pressed OK:", harness.click("Export MusicXML", "OK"), flush=True)
        run.join(600)
        folders = [p for p in run_lua.RUN_DIR.glob("Flows from *") if p not in before]
        report = {"source": str(source), "flows": []}
        for flow in facts["flows"]:
            dumped = flow["notes"]
            files = [f for d in folders for f in d.glob(f"* - Full score - {flow['number']:02d} *.musicxml")]
            entry = {"number": flow["number"], "dumped": len(dumped), "files": [f.name for f in files]}
            if files:
                parts = read_musicxml(files[0])
                ours = Counter()
                by_player = {}
                for n in dumped:
                    name, pos, spelling, grace = n.split("|")
                    k = key(float(pos), *from_spelling(spelling), grace == "true")
                    ours[k] += 1
                    by_player.setdefault(name, Counter())[k] += 1
                theirs = Counter(k for notes in parts.values() for k in notes)
                entry["exported"] = sum(theirs.values())
                entry["onlyDumped"] = sorted((ours - theirs).elements())[:20]
                entry["onlyExported"] = sorted((theirs - ours).elements())[:20]
                entry["partNames"] = list(parts.keys())
                entry["playerNames"] = list(by_player.keys())
                entry["pairs"] = {name: [part for part, notes in parts.items() if Counter(notes) == c]
                                  for name, c in by_player.items()}
            report["flows"].append(entry)
            print(json.dumps(entry, indent=1), flush=True)
        (OUT / f"{source.stem}.json").write_text(json.dumps(report, indent=1), encoding="utf-8")
        for d in folders:
            shutil.rmtree(d)
    finally:
        if verified and sid is not None:
            print("closed", run_lua.close_scratch(client, sid))
        client.close()


if __name__ == "__main__":
    main()
