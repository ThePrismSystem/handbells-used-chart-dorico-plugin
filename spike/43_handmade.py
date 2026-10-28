"""Where does the chart go in a project that had a hand-made one?

    python spike/43_handmade.py PROJECT.dorico [FLOW_NAME]

On one scratch copy of PROJECT this:
  1. probes the pages with spike/42_placement.lua and captures pages 1-3 (as sent);
  2. deletes the hand-made chart's flow (FLOW_NAME, default BUC) with spike/43_delete_flow.lua, confirming Dorico's
     Delete Flow, then probes and captures again;
  3. draws the plug-in's combined chart with the music following it (tests/dorico/case_write.lua, newPage false),
     then probes and captures again.
Probe results and captures go to %TEMP%\\hbuc-run\\43 as <step>.json and <step>-page<n>.png. The copy is closed
unsaved.
"""
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CASES = REPO / "tests" / "dorico"
sys.path.insert(0, str(CASES))
import harness  # noqa: E402
import dws  # noqa: E402
import run_lua  # noqa: E402
import snap  # noqa: E402

OUT = run_lua.RUN_DIR / "43"
PLACEMENT = REPO / "spike" / "42_placement.lua"
DELETE = REPO / "spike" / "43_delete_flow.lua"
PAGES = (1, 2, 3)


def run_more(client, script, args=None):
    extra = dict(args or {})
    extra["expectScratch"] = {"path": run_lua.fwd(harness.SCRATCH)}
    code, result, _ = run_lua.run(script, on_active=True, extra_args=extra, timeout=600, client=client)
    if not result or not result.get("facts", {}).get("scratchVerified"):
        raise RuntimeError(f"{script.name} did not run on the scratch copy (exit {code}): {json.dumps(result)[:2000]}")
    failed = [c for c in result.get("checks", []) if not c["ok"]]
    print(f"== {script.name}: exit {code}, failed {json.dumps(failed)}, error {json.dumps(result.get('error'))[:1500]}",
          flush=True)
    return result


def record(client, step):
    result = run_more(client, PLACEMENT)
    (OUT / f"{step}.json").write_text(json.dumps(result, indent=1), encoding="utf-8")
    for line in result["facts"]["flows"] + result["facts"]["pages"]:
        print(f"    {line}", flush=True)
    client.command("Window.SwitchMode?WindowMode=kWriteMode")
    for n in PAGES:
        snap.snap(OUT / f"{step}-page{n}.png", page=n, client=client)
    print(f"    captured {step}-page1..{PAGES[-1]}.png", flush=True)


def main():
    source = Path(sys.argv[1])
    flow_name = sys.argv[2] if len(sys.argv) > 2 else "BUC"
    OUT.mkdir(parents=True, exist_ok=True)
    client = dws.DoricoClient()
    client.connect()
    code, result, sid = run_lua.run(PLACEMENT, open_file=source, keep_open=True, client=client, timeout=600)
    verified = bool(((result or {}).get("facts") or {}).get("scratchVerified"))
    try:
        if not verified:
            print(f"the scratch copy could not be confirmed (exit {code}): {json.dumps(result)[:2000]}")
            return
        sid = result["facts"].get("scratchScoreID", sid)
        print("== as sent", flush=True)
        record(client, "sent")

        deleting = harness.Background(lambda: run_more(client, DELETE, {"name": flow_name}))
        if harness.wait_for_window(title="Delete Flow") != "Delete Flow" or not harness.click("Delete Flow", "OK"):
            raise RuntimeError("Dorico's Delete Flow did not appear")
        deleting.join(300)
        print(f"== without {flow_name}", flush=True)
        record(client, "deleted")

        run_more(client, CASES / "case_write.lua", {"mode": "combined", "newPage": False})
        print("== with the plug-in's chart", flush=True)
        record(client, "drawn")
    finally:
        if verified and sid is not None:
            run_lua.close_scratch(client, sid)
        client.close()


if __name__ == "__main__":
    main()
