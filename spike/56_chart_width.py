"""Does a chart stay on one system at the size chartlayout.staffPercent gives?

    python spike/56_chart_width.py

Dorico can't report the systems it made, so this is checked by eye. Each chart below is drawn on a fresh scratch copy
of the fixture with spike/56_chart_width.lua, and page 1 is captured to %TEMP%\\hbuc-run\\56\\<name>.png. Each copy is
closed unsaved. On each capture, every section should be on one system, with no short system after it holding only
the hidden end note.
"""
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tests" / "dorico"))
import harness  # noqa: E402
import dws  # noqa: E402
import run_lua  # noqa: E402
import snap  # noqa: E402

OUT = run_lua.RUN_DIR / "56"
CHARTS = {
    "plain-30": {"sections": [30], "kind": "plain"},
    "plain-35": {"sections": [35], "kind": "plain"},
    "accidentals-40": {"sections": [40], "kind": "accidentals"},
    "not-the-last-section": {"sections": [30, 5], "kind": "accidentals"},
    "tight-plain": {"sections": [40], "kind": "plain", "crotchet": "5/2"},
    "tight-accidentals": {"sections": [40], "kind": "accidentals", "crotchet": "5/2"},
}


def draw(name, args):
    client = dws.DoricoClient()
    client.connect()
    code, result, sid = run_lua.run(REPO / "spike" / "56_chart_width.lua", open_file=harness.FIXTURE, keep_open=True,
                                    extra_args=args, client=client, timeout=600)
    facts = (result or {}).get("facts") or {}
    verified = bool(facts.get("scratchVerified"))
    try:
        if not verified:
            print(f"== {name}: NOT VERIFIED (exit {code}), skipped", flush=True)
            return
        sid = facts.get("scratchScoreID", sid)
        status = "drawn" if result.get("ok") else f"FAILED {json.dumps(result.get('error'))[:500]}"
        print(f"== {name}: {status} at {facts.get('staffPercent')}%, page {facts.get('page')}", flush=True)
        out = OUT / f"{name}.png"
        snap.snap(out, page=1, client=client)
        print(f"    captured {out}", flush=True)
    finally:
        if verified and sid is not None:
            run_lua.close_scratch(client, sid)
        client.close()


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for chart, chart_args in CHARTS.items():
        draw(chart, chart_args)
