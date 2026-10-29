"""Check that a real project's dumped notes map one for one onto the note events of a copy saved by app:save.

  python spike/54_real_map.py PROJECT.dorico

Opens a scratch copy of PROJECT (answering the factory playback template prompt with Continue), runs
spike/54_real_map.lua, closes the copy unsaved, decodes the saved copy's score.dtn with spike/lib/dtn.py, and
compares event ids, positions and pitches, and the notes Lua lists as having a notehead override.
"""
import json
import sys
import time
from collections import Counter
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "dorico"))
sys.path.insert(0, str(ROOT / "tests" / "dorico"))
sys.path.insert(0, str(ROOT / "spike" / "lib"))
import dtn  # noqa: E402
import dws  # noqa: E402
import harness  # noqa: E402
import run_lua  # noqa: E402

LUA = ROOT / "spike" / "54_real_map.lua"
COPY = run_lua.RUN_DIR / "54-copy.dorico"
STEPS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(spelling):
    """'C#5' -> 73 (C4 = 60); accidentals # b x bb."""
    letter, rest = spelling[0], spelling[1:]
    acc = 0
    while rest and rest[0] in "#bx":
        acc += {"#": 1, "b": -1, "x": 2}[rest[0]]
        rest = rest[1:]
    return 12 * (int(rest) + 1) + STEPS[letter] + acc


def events(tree):
    names, values, nodes = tree["names"], tree["values"], tree["nodes"]

    def child(node, name):
        for k in nodes[node][3]:
            if names[nodes[k][1]] == name:
                return k
        return None

    out = {}
    for i, (_, name, _, _) in enumerate(nodes):
        kind = names[name]
        if kind not in ("NoteEventDefinition", "GraceNoteEventDefinition"):
            continue
        get = lambda n: values[nodes[child(i, n)][2]] if child(i, n) is not None else None  # noqa: E731
        heads = []
        table = child(i, "propertyTable")
        entries = child(table, "entries") if table is not None else None
        for e in (nodes[entries][3] if entries is not None else []):
            if values[nodes[child(e, "propertyType")][2]] == "kNoteheadSetOverride":
                heads.append(values[nodes[child(e, "value")][2]])
        out[int(get("eventID"))] = {"kind": kind, "pos": get("position"), "pitch": get("pitch"), "heads": heads}
    return out


def main():
    project = Path(sys.argv[1])

    client = dws.DoricoClient()
    client.connect()
    job = harness.Background(lambda: run_lua.run(LUA, open_file=project, client=client, timeout=900,
                                                 extra_args={"file": run_lua.fwd(COPY)}))
    deadline = time.time() + 120
    while job.thread.is_alive() and time.time() < deadline:
        if "Dorico" in run_lua.open_windows():
            print("answered a prompt:", harness.click("Dorico", "Continue"), flush=True)
        time.sleep(2)
    code, result, _ = job.join()
    client.close()
    facts = (result or {}).get("facts") or {}
    if code != 0:
        print("run failed", code, json.dumps({"error": (result or {}).get("error"), "checks": (result or {}).get("checks")},
                                             indent=1)[:3000])
        return 1
    print("save took", facts["saveSeconds"], "s; streams read", facts["streamsRead"], "threw", facts["streamsThrew"])

    ev = events(dtn.read(COPY))
    missing, pos_off, pitch_off, matched = [], [], [], 0
    for n in facts["notes"]:
        e = ev.get(n["id"])
        if e is None:
            missing.append(n)
            continue
        matched += 1
        if not n["grace"] and Fraction(e["pos"]) != Fraction(n["pos"]).limit_denominator(10000):
            pos_off.append((n, e["pos"]))
        if e["pitch"] is not None and int(e["pitch"]) != midi(n["spelling"]):
            pitch_off.append((n, e["pitch"]))
    print(f"dump notes {len(facts['notes'])}, matched by id {matched}, missing {len(missing)}, "
          f"position differs {len(pos_off)}, pitch differs {len(pitch_off)}; saved note events {len(ev)}")
    for label, rows in (("missing", missing), ("position", pos_off), ("pitch", pitch_off)):
        for r in rows[:5]:
            print(" ", label, r)
    listed = set(facts["listedIds"])
    with_head = {i for i, e in ev.items() if e["heads"]}
    readable = {i for i in listed}
    print("Lua-listed overrides", len(listed), "| saved entries among them", len(listed & with_head),
          "| listed but no saved entry", len(readable - with_head))
    dumped = {n["id"] for n in facts["notes"]}
    print("heads on dumped notes:", dict(Counter(h for i in dumped & with_head for h in ev[i]["heads"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
