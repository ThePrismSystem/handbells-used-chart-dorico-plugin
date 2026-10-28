"""How far apart must the last section's columns be for Dorico to fit it to the page's width?

    python spike/41_last_step.py [STEP...]

The last chart section is the chart flow's final system, which Dorico stretches only when it is already at least
the full score's final-system threshold wide (50% by default; spike/40_last_system.py). writechart spreads that
section's columns chartlayout.LAST_STEP beats apart, with a hidden note one step after its last column, so it is
wider than the frame and Dorico has to fit it to the width. For each step (default 1, 16, 64, 256, 1024, 4096) this
draws the fixture's combined chart on a fresh scratch copy with tests/dorico/case_write.lua, which checks the chart
through the object model, and captures page 1 to %TEMP%\\hbuc-run\\41\\step-<n>.png. Step 1 is the chart as it was.
Each copy is closed unsaved.

On each capture, look at the last section (Whitechapel Handbells Used: 2): do its staff lines reach the right
margin, and are its notes spaced like the sections above (each column's share of the width, the last one included)?
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

OUT = run_lua.RUN_DIR / "41"
STEPS = [1, 16, 64, 256, 1024, 4096]


def draw(step):
    client = dws.DoricoClient()
    client.connect()
    code, result, sid = run_lua.run(CASES / "case_write.lua", open_file=harness.FIXTURE, keep_open=True,
                                    extra_args={"mode": "combined", "lastStep": step}, client=client, timeout=600)
    facts = (result or {}).get("facts") or {}
    verified = bool(facts.get("scratchVerified"))
    try:
        if not verified:
            print(f"== step {step}: NOT VERIFIED (exit {code}), skipped", flush=True)
            return
        sid = facts.get("scratchScoreID", sid)
        failed = [c["name"] for c in (result or {}).get("checks", []) if not c["ok"]]
        status = "checks pass" if result.get("ok") else f"FAILED {failed or json.dumps(result.get('error'))[:500]}"
        print(f"== step {step}: {status}, drawn in {facts.get('writeSeconds', 0):.1f}s", flush=True)
        out = OUT / f"step-{step}.png"
        snap.snap(out, page=1, client=client)
        print(f"    captured {out}", flush=True)
    finally:
        if verified and sid is not None:
            run_lua.close_scratch(client, sid)
        client.close()


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for step in [int(a) for a in sys.argv[1:]] or STEPS:
        draw(step)
