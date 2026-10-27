"""Run the chart recipe (spike/11_chart_recipe.lua) on a fixture copy and check what Lua cannot read back.

    python spike/run_recipe.py

Checks the full-score layout options and the per-flow notation options through the Remote API,
captures the page to docs/spike/recipe.png, saves the probe's result to docs/spike/results/, and closes
the copy. Exit code 0 when every check passes.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "dorico"))
import dws  # noqa: E402
import run_lua  # noqa: E402
import snap  # noqa: E402

RESULTS = ROOT / "docs" / "spike" / "results"
CROP = ROOT / "tools" / "dorico" / "crop.ps1"


def options(client, kind, key, ident):
    client.send({"message": "getoptions", "optionsType": kind, key: ident})
    while True:
        reply = client.recv()
        if reply.get("message") == "optionslist":
            return {o["path"]: o.get("currentValue") for o in reply["options"]}
        if reply.get("message") == "response":
            raise RuntimeError(f"getoptions {kind} {ident}: {reply}")


def main():
    RESULTS.mkdir(parents=True, exist_ok=True)
    client = dws.DoricoClient()
    client.connect()
    failures = []
    try:
        code, result, scratch = run_lua.run(ROOT / "spike" / "11_chart_recipe.lua", open_file=ROOT / "fixtures" / "handbells-fixture.dorico",
                                            keep_open=True, client=client, timeout=300)
        if result is None:
            print("no result")
            return 2
        (RESULTS / "11_chart_recipe.json").write_text(json.dumps(result, indent=1, ensure_ascii=False), encoding="utf-8")
        for c in result.get("checks", []):
            print(f"  {'ok  ' if c['ok'] else 'FAIL'} {c['label']} {c.get('detail') or ''}"[:300])
            if not c["ok"]:
                failures.append(c["label"])
        if result.get("error"):
            failures.append("error: " + result["error"][:500])
        facts = result.get("facts", {})
        if not facts.get("scratchVerified"):
            print("scratch not verified; leaving it open")
            return 2

        layout = options(client, "kLayout", "layoutID", 0)
        chart_id = facts["chartFlowId"]
        expected_layout = {
            "flowHeadingBehaviour": "kNoFlowHeadings",
            "hideEmptyStavesPolicy": "kAllSystems",
            "alwaysVisiblePlayers": facts["musicPlayerIds"],
            "staffLabelLayoutOptions.playersToShowPlayerName": facts["chartPlayerIds"],
        }
        for path, want in expected_layout.items():
            got = layout.get(path)
            ok = got == want
            print(f"  {'ok  ' if ok else 'FAIL'} layout {path} = {got!r} (want {want!r})")
            if not ok:
                failures.append(f"layout {path}")
        chart_notation = options(client, "kNotation", "flowID", chart_id)
        music_notation = options(client, "kNotation", "flowID", 0)
        for flow_name, notation, want in (("chart", chart_notation, ("kNone", "kNone")),
                                          ("music", music_notation, ("kFinal", "kNormal"))):
            got = (notation.get("barlineOptions.finalBarlineType"), notation.get("barlineOptions.defaultBarlineType"))
            ok = got == want
            print(f"  {'ok  ' if ok else 'FAIL'} {flow_name} flow barlines (final, default) = {got} (want {want})")
            if not ok:
                failures.append(f"{flow_name} flow barlines")
        (RESULTS / "11_chart_recipe_options.json").write_text(json.dumps({
            "layout": {k: layout.get(k) for k in expected_layout},
            "chartFlowNotation": {k: chart_notation.get(k) for k in ("barlineOptions.finalBarlineType", "barlineOptions.defaultBarlineType")},
            "musicFlowNotation": {k: music_notation.get(k) for k in ("barlineOptions.finalBarlineType", "barlineOptions.defaultBarlineType")},
        }, indent=1), encoding="utf-8")

        whole = run_lua.RUN_DIR / "recipe-whole.png"
        snap.snap(whole, zoom="whole", client=client)
        subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(CROP), "-In", str(whole),
                        "-Out", str(ROOT / "docs" / "spike" / "recipe.png"), "-X", "340", "-Y", "330", "-Width", "1150",
                        "-Height", "900"], check=True, capture_output=True)
        print("captured docs/spike/recipe.png")
        run_lua.close_scratch(client, scratch)
    finally:
        client.close()
    print("ALL PASS" if not failures else f"{len(failures)} FAILED: {failures}")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
