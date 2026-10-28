"""Why does the chart's last section sometimes stop short of the page's width?

    python spike/40_last_system.py

Every section but the last ends at a system break, so Dorico justifies it. The last one is the chart flow's final
system, which the full score's noteSpacingJustificationOptions decide. Yet the fixture's pictures show the last
section justified at a fraction of the threshold the first spike reported (50%). On one scratch copy of the fixture
this:
  1. draws the combined chart with tests/dorico/case_write.lua;
  2. prints the full score's layout options and the chart flow's notation options whose names mention
     justification or spacing, and captures pages 1 and 2 (is anything of the chart flow on page 2?);
  3. turns the final-system threshold on at 50% with spike/40_layout.lua, prints the options again and captures
     page 1, to see whether that leaves the last section short.
The captures are written to %TEMP%\\hbuc-run\\40. The copy is closed unsaved.
"""
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CASES = REPO / "tests" / "dorico"
sys.path.insert(0, str(CASES))
import harness  # noqa: E402
import dws  # noqa: E402
import run_lua  # noqa: E402
import snap  # noqa: E402

LAYOUT = REPO / "spike" / "40_layout.lua"
OUT = run_lua.RUN_DIR / "40"
WANTED = re.compile("justif|spacing", re.I)
THRESHOLD_ON = {
    "noteSpacingJustificationOptions.useFinalSystemJustificationThreshold": "true",
    "noteSpacingJustificationOptions.finalSystemJustificationThreshold": "50",
}


def run_more(client, script, args=None):
    extra = dict(args or {})
    extra["expectScratch"] = {"path": run_lua.fwd(harness.SCRATCH)}
    code, result, _ = run_lua.run(script, on_active=True, extra_args=extra, timeout=600, client=client)
    if not result or not result.get("ok"):
        raise RuntimeError(f"{script.name} failed (exit {code}): {json.dumps(result)[:2000]}")
    return result["facts"]


def show_options(client, chart_flow):
    for kind, key, ident in (("kLayout", "layoutID", 0), ("kNotation", "flowID", chart_flow)):
        for path, value in sorted(harness.options(client, kind, key, ident).items()):
            if WANTED.search(path):
                print(f"    {kind} {path} = {value}", flush=True)


def capture(client, name, page=1):
    out = OUT / f"{name}.png"
    snap.snap(out, page=page, client=client)
    print(f"    captured {out}", flush=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    client = dws.DoricoClient()
    client.connect()
    code, result, sid = run_lua.run(CASES / "case_write.lua", open_file=harness.FIXTURE, keep_open=True,
                                    extra_args={"mode": "combined"}, client=client, timeout=600)
    facts = (result or {}).get("facts") or {}
    verified = bool(facts.get("scratchVerified"))
    try:
        if not verified or not result.get("ok"):
            print(f"case_write failed (exit {code}): {json.dumps(result)[:2000]}")
            return
        sid = facts.get("scratchScoreID", sid)
        print("== as drawn:", ", ".join(facts.get("labels") or []), flush=True)
        show_options(client, facts["chartFlowId"])
        capture(client, "drawn-page1")
        capture(client, "drawn-page2", page=2)
        print("== final-system threshold on at 50%", flush=True)
        run_more(client, LAYOUT, {"options": THRESHOLD_ON})
        show_options(client, facts["chartFlowId"])
        capture(client, "threshold-page1")
    finally:
        if verified and sid is not None:
            run_lua.close_scratch(client, sid)
        client.close()


if __name__ == "__main__":
    main()
