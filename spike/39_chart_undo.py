"""What does one Edit > Undo take back after a run that draws a chart?

    python spike/39_chart_undo.py

The README's note on undo dated from when object-model edits were thought never to enter the undo history. Later
probes found they do: a run's edits are one undo step, and after an Edit.Undo inside a run, what the run does next
joins the user's previous step. This checks what that means for a whole chart, on two scratch copies of the fixture:
  * paste: the music is read through a copy, so the run's one Edit.Undo comes before the drawing;
  * direct: every flow is read directly, so the run has no undo of its own.
Each copy gets an edit of the user's own first (the music flow renamed, in a script run of its own). Then
tests/dorico/case_write.lua draws a chart with the plug-in's own read and write (no dialog and no save), and one
Edit > Undo is sent through the Remote API. spike/39_chart_state.lua lists the flows and players after the run and
after the undo. Each copy is closed unsaved.

On Dorico 6.2.30 the undo took the whole chart away on both copies, layout options included, and on the paste copy
the user's rename as well. The findings are in docs/dorico-lua-guide.md, section 7.
"""
import json
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CASES = REPO / "tests" / "dorico"
sys.path.insert(0, str(CASES))
import harness  # noqa: E402
import dws  # noqa: E402
import run_lua  # noqa: E402

STATE = REPO / "spike" / "39_chart_state.lua"


def run_more(client, script, args=None):
    extra = dict(args or {})
    extra["expectScratch"] = {"path": run_lua.fwd(harness.SCRATCH)}
    code, result, _ = run_lua.run(script, on_active=True, extra_args=extra, timeout=600, client=client)
    if not result or not result.get("ok"):
        raise RuntimeError(f"{script.name} failed (exit {code}): {json.dumps(result)[:2000]}")
    return result["facts"]


def show(client, label, facts):
    flows = "; ".join(f"{f['title']} ({f['notes']} notes, {f['players']} players)" for f in facts["flows"])
    layout = harness.options(client, "kLayout", "layoutID", 0)
    print(f"  {label}: {flows}", flush=True)
    print(f"    players: {', '.join(facts['players'])}", flush=True)
    print(f"    flowHeadingBehaviour {layout.get('flowHeadingBehaviour')},"
          f" hideEmptyStavesPolicy {layout.get('hideEmptyStavesPolicy')}", flush=True)


def scenario(name, force_paste):
    client = dws.DoricoClient()
    client.connect()
    code, result, sid = run_lua.run(STATE, open_file=harness.FIXTURE, keep_open=True, client=client, timeout=300)
    facts = (result or {}).get("facts") or {}
    verified = bool(facts.get("scratchVerified"))
    print("==", name, "" if verified else f"NOT VERIFIED (exit {code}), skipped", flush=True)
    try:
        if not verified:
            return
        sid = facts.get("scratchScoreID", sid)
        show(client, "start", facts)
        run_more(client, CASES / "case_titles.lua", {"renameFirstFlow": "User Edit"})
        run_more(client, CASES / "case_write.lua", {"mode": "combined", "forcePaste": force_paste})
        show(client, "after the run", run_more(client, STATE))
        client.command("Edit.Undo")
        # Dorico may still be applying the undo when the command returns
        time.sleep(1)
        show(client, "after one Edit > Undo", run_more(client, STATE))
    finally:
        if verified and sid is not None:
            run_lua.close_scratch(client, sid)
        client.close()


if __name__ == "__main__":
    scenario("paste", True)
    scenario("direct", False)
