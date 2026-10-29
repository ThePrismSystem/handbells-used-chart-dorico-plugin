"""Every built-in notehead set, chosen by command, read back from a copy saved by app:save.

Runs spike/53_dtn_survey.lua on a scratch copy of the fixture (closed unsaved afterwards), decodes the saved
copy's score.dtn with spike/lib/dtn.py, then compares each note's kNoteheadSetOverride and kEventColour with what
was set.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "dorico"))
sys.path.insert(0, str(ROOT / "spike" / "lib"))
import dtn  # noqa: E402
import dws  # noqa: E402
import run_lua  # noqa: E402

LUA = ROOT / "spike" / "53_dtn_survey.lua"
FIXTURE = ROOT / "fixtures" / "handbells-fixture.dorico"
COPY = run_lua.RUN_DIR / "53-copy.dorico"
LIBRARY = Path(r"C:\Program Files\Steinberg\Dorico6\scorelibrary.xml")


def note_properties(tree, event_id):
    """{propertyType: [(value, context text)]} of the NoteEventDefinition with this eventID."""
    names, values, nodes = tree["names"], tree["values"], tree["nodes"]

    def child(node, name):
        for k in nodes[node][3]:
            if names[nodes[k][1]] == name:
                return k
        return None

    def text(node):
        tag, name, value, kids = nodes[node]
        return names[name] + ("=" + values[value] if values[value] else "") + (
            "(" + ",".join(text(k) for k in kids) + ")" if kids else "")

    for i, (tag, name, value, kids) in enumerate(nodes):
        if names[name] != "NoteEventDefinition":
            continue
        idn = child(i, "eventID")
        if idn is None or values[nodes[idn][2]] != str(event_id):
            continue
        out = {}
        table = child(i, "propertyTable")
        entries = child(table, "entries") if table is not None else None
        for e in (nodes[entries][3] if entries is not None else []):
            ptype = values[nodes[child(e, "propertyType")][2]]
            val = values[nodes[child(e, "value")][2]]
            ctx = child(e, "context")
            out.setdefault(ptype, []).append((val, text(ctx) if ctx is not None else ""))
        return out
    return None


def main():
    ids = sorted(set(re.findall(r"<entityID>(noteheadset\.[A-Za-z0-9_]+)</entityID>", LIBRARY.read_text("utf-8"))))
    ids.remove("noteheadset.default")

    client = dws.DoricoClient()
    client.connect()
    score_id, verified, result = None, False, None
    try:
        code, result, score_id = run_lua.run(LUA, open_file=FIXTURE, keep_open=True, client=client, timeout=600,
                                             extra_args={"step": "setup", "ids": ids})
        facts = (result or {}).get("facts") or {}
        verified = bool(facts.get("scratchVerified"))
        if code != 0 or not verified:
            print("setup failed", code, json.dumps(result, indent=1)[:3000])
            return 1
        score_id = facts.get("scratchScoreID", score_id)
        expect = {"path": run_lua.fwd(run_lua.RUN_DIR / "scratch.dorico")}
        saved = run_lua.run(LUA, on_active=True, client=client, extra_args={
            "step": "save", "file": run_lua.fwd(COPY), "expectScratch": expect})
        if saved[0] != 0:
            print("save failed", json.dumps(saved[1], indent=1)[:3000])
            return 1
    finally:
        if verified and score_id is not None:
            run_lua.close_scratch(client, score_id)
        client.close()

    tree = dtn.read(COPY)
    right = wrong = 0
    for n in facts["notes"]:
        props = note_properties(tree, n["eventId"]) or {}
        heads = props.get("kNoteheadSetOverride", [])
        colours = props.get("kEventColour", [])
        ok = [v for v, _ in heads] == [f'string: "{n["head"]}"']
        if n.get("colour"):
            ok = ok and len(colours) == 1 and n["colour"][1:] in colours[0][0].lower()
        right += ok
        wrong += not ok
        if not ok or n["eventId"] == facts["notes"][0]["eventId"] or n.get("colour") and right < 4:
            print(n, "->", json.dumps({"heads": heads, "colours": colours}))
    print(f"{right} of {right + wrong} notes read back as set")
    return 0 if wrong == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
