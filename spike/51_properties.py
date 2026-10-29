"""What the Remote API's getproperties and getlibraryentities say about notehead sets set by command.

Runs spike/51_properties.lua on a scratch copy of the fixture, asks the Remote API about each selected note, and
writes every reply to <run dir>/51_properties.json. Read-only apart from the scratch copy, which it closes unsaved.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "dorico"))
import dws  # noqa: E402
import run_lua  # noqa: E402

LUA = ROOT / "spike" / "51_properties.lua"
FIXTURE = ROOT / "fixtures" / "handbells-fixture.dorico"
HEADS = ["noteheadset.rectangular", "noteheadset.oldDiamondNoteheads", "noteheadset.wideDiamondNoteheads"]
SAVED = run_lua.RUN_DIR / "51-heads-by-command.dorico"


def ask(client, msg, expect, limit=50):
    """Send msg and return the reply of kind expect, or the error response that comes instead."""
    client.send(msg)
    for _ in range(limit):
        reply = client.recv()
        kind = reply.get("message")
        if kind == expect or (kind == "response" and reply.get("code") != "kOK"):
            return reply
    return None


def main():
    out = {}
    client = dws.DoricoClient()
    client.connect()
    score_id, verified = None, False
    try:
        code, result, score_id = run_lua.run(LUA, open_file=FIXTURE, keep_open=True, client=client, timeout=300,
                                             extra_args={"step": "setup", "heads": HEADS})
        out["setup"] = result
        facts = (result or {}).get("facts") or {}
        verified = bool(facts.get("scratchVerified"))
        if code != 0 or not verified:
            print("setup failed", code, json.dumps(result, indent=1)[:3000])
            return 1
        score_id = facts.get("scratchScoreID", score_id)
        expect = {"path": run_lua.fwd(run_lua.RUN_DIR / "scratch.dorico")}
        out["getproperties"] = []
        for i, s in enumerate(facts["set"]):
            if i > 0:
                run_lua.run(LUA, on_active=True, client=client, extra_args={
                    "step": "select", "flowId": facts["flowId"], "eventId": s["eventId"], "blockId": s["blockId"],
                    "expectScratch": expect})
            out["getproperties"].append({"head": s["head"], "reply": ask(client, {"message": "getproperties"},
                                                                          "propertieslist")})
        out["getlibrarycollections"] = ask(client, {"message": "getlibrarycollections"}, "librarycollectionslist")
        out["getlibraryentities"] = ask(client, {"message": "getlibraryentities",
                                                 "collection": "kNoteheadSetCollection"}, "libraryentitieslist")
        out["contexts"] = run_lua.run(LUA, on_active=True, client=client, extra_args={
            "step": "contexts", "flowId": facts["flowId"], "streamId": facts["streamId"],
            "eventId": facts["set"][0]["eventId"], "expectScratch": expect,
            "contexts": json.loads(sys.argv[1]) if len(sys.argv) > 1 else []})[1]
        out["saveas"] = run_lua.run(LUA, on_active=True, client=client, extra_args={
            "step": "saveas", "file": run_lua.fwd(SAVED), "expectScratch": expect})[1]
    finally:
        path = run_lua.RUN_DIR / "51_properties.json"
        path.write_text(json.dumps(out, indent=1), encoding="utf-8")
        print("wrote", path)
        if verified and score_id is not None:
            run_lua.close_scratch(client, score_id)
        client.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
