"""Does app:save(score, path) clear the project's unsaved-changes mark (the "*" ending Dorico's window title)?

On a scratch copy of the fixture: an edit, the title, app:save to a copy, the title again. Closes the copy unsaved.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "dorico"))
import dws  # noqa: E402
import run_lua  # noqa: E402

LUA = ROOT / "spike" / "52_save_copy.lua"
FIXTURE = ROOT / "fixtures" / "handbells-fixture.dorico"
COPY = run_lua.RUN_DIR / "52-copy.dorico"


def scratch_titles():
    return [t for t in run_lua.window_titles() if "scratch" in t]


def main():
    out = {}
    client = dws.DoricoClient()
    client.connect()
    score_id, verified = None, False
    try:
        out["titlesBefore"] = scratch_titles()
        code, result, score_id = run_lua.run(LUA, open_file=FIXTURE, keep_open=True, client=client, timeout=300,
                                             extra_args={"step": "edit", "file": run_lua.fwd(COPY)})
        facts = (result or {}).get("facts") or {}
        verified = bool(facts.get("scratchVerified"))
        if code != 0 or not verified:
            print("edit failed", code, json.dumps(result, indent=1)[:3000])
            return 1
        score_id = facts.get("scratchScoreID", score_id)
        client.settle()
        out["titlesAfterEdit"] = scratch_titles()
        expect = {"path": run_lua.fwd(run_lua.RUN_DIR / "scratch.dorico")}
        out["save"] = run_lua.run(LUA, on_active=True, client=client, extra_args={
            "step": "save", "command": "lua", "file": run_lua.fwd(COPY), "expectScratch": expect})[1]
        client.settle()
        out["titlesAfterSave"] = scratch_titles()
    finally:
        print(json.dumps({k: v for k, v in out.items() if k.startswith("titles")}, indent=1))
        print(json.dumps(((out.get("save") or {}).get("facts") or {}).get("command")))
        if verified and score_id is not None:
            run_lua.close_scratch(client, score_id)
        client.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
