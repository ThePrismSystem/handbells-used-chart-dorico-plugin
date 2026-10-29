"""Which of Dorico's built-in notehead sets survive a MusicXML export?

    python spike/48_notehead_survey.py [BEATS]

BEATS is each note's length in quarters (default 1; 2 for half notes).

Runs spike/48_notehead_survey.lua on a scratch copy of the fixture: a new flow with one note per built-in set (the
ids in hbuc/shapes.lua), set from Lua on one player and by command (as the UI does) on another. Presses OK in
Dorico's "Export MusicXML" dialog, then reads the new flow's full-score file and records, per set, the <notehead>
text and attributes of each copy. Output: %TEMP%\\hbuc-run\\48\\survey-<BEATS>.json. The copy is closed unsaved.
"""
import json
import re
import shutil
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tests" / "dorico"))
import harness  # noqa: E402
import dws  # noqa: E402
import run_lua  # noqa: E402

SCRIPT = REPO / "spike" / "48_notehead_survey.lua"
SHAPES = REPO / "plugin" / "Handbells Used Chart" / "hbuc" / "shapes.lua"
OUT = run_lua.RUN_DIR / "48"
EXPORTS = run_lua.RUN_DIR / "Flows from Handbells Chart Fixture"


def set_ids():
    text = SHAPES.read_text(encoding="utf-8")
    block = text[text.index("local DISPLAY = {"):text.index("local BUILT_IN_SHAPE")]
    return re.findall(r'\["(noteheadset\.[^"]+)"\]', block)


def heads(part):
    out = []
    for note in part.iter("note"):
        if note.find("pitch") is None:
            continue
        nh = note.find("notehead")
        out.append({"notehead": None if nh is None else nh.text, "attributes": {} if nh is None else dict(nh.attrib),
                    "type": note.findtext("type")})
    return out


def main():
    ids = set_ids()
    beats = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    print(len(ids), "sets,", beats, "beats each", flush=True)
    OUT.mkdir(parents=True, exist_ok=True)
    if EXPORTS.exists():
        shutil.rmtree(EXPORTS)  # an earlier spike's export: Dorico would otherwise ask about the existing folder
    client = dws.DoricoClient()
    client.connect()
    code, result, _ = run_lua.run(SCRIPT, open_file=harness.FIXTURE, keep_open=True, client=client, timeout=900,
                                  extra_args={"ids": ids, "beats": beats})
    facts = (result or {}).get("facts") or {}
    print("build: exit", code, "error", (result or {}).get("error"), flush=True)
    try:
        if not facts.get("scratchVerified"):
            return
        extra = {"step": "export", "expectScratch": {"path": run_lua.fwd(harness.SCRATCH)}}
        run = harness.Background(lambda: run_lua.run(SCRIPT, on_active=True, client=client, timeout=900,
                                                     extra_args=extra))
        if harness.wait_for_window(timeout=600, title="Export MusicXML") != "Export MusicXML":
            print("the export dialog did not appear; windows:", run_lua.open_windows())
        else:
            time.sleep(1)
            print("pressed OK:", harness.click("Export MusicXML", "OK"), flush=True)
        code, exported, _ = run.join(600) or (None, None, None)
        print("export: exit", code, "error", (exported or {}).get("error"), flush=True)
        # A new flow's number token is 00 and its title "Flow <n>": take the full score of whichever flow isn't the
        # fixture's own.
        files = [f for f in sorted(EXPORTS.glob("* - Full score - *.musicxml")) if "Handbells Chart Fixture" not in f.name]
        print("files", [f.name for f in files])
        if not files:
            return
        root = ET.parse(files[0]).getroot()  # noqa: S314 (the export Dorico just wrote into the run folder)
        parts = root.findall("part")
        by_lua, by_command = heads(parts[0]), heads(parts[1])
        rows = []
        for i, id_ in enumerate(ids):
            rows.append({"set": id_, "lua": by_lua[i] if i < len(by_lua) else None,
                         "command": by_command[i] if i < len(by_command) else None,
                         "readByLua": (facts.get("readByLua") or [None] * len(ids))[i],
                         "readByCommand": (facts.get("readByCommand") or [None] * len(ids))[i]})
        (OUT / f"survey-{beats}.json").write_text(json.dumps({"file": str(files[0]), "notes": [len(by_lua), len(by_command)],
                                                     "rows": rows}, indent=1), encoding="utf-8")
        print("notes per part", len(by_lua), len(by_command))
        for r in rows:
            lua, cmd = r["lua"] or {}, r["command"] or {}
            same = (lua.get("notehead"), lua.get("attributes")) == (cmd.get("notehead"), cmd.get("attributes"))
            print(f"{r['set']:42} {lua.get('notehead')!s:20} {json.dumps(lua.get('attributes'))!s:40} "
                  f"{'same' if same else 'COMMAND: ' + str(cmd.get('notehead')) + ' ' + json.dumps(cmd.get('attributes'))}")
    finally:
        if facts.get("scratchVerified"):
            print("closed", run_lua.close_scratch(client, facts["scratchScoreID"]))
        client.close()


if __name__ == "__main__":
    main()
