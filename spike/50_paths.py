"""Make an export folder with an accent in its name, then run spike/50_paths.lua on a scratch copy of the fixture.

    python spike/50_paths.py

Prints the probe's facts and deletes the folder again.
"""
import json
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tests" / "dorico"))
import harness  # noqa: E402
import run_lua  # noqa: E402

folder = run_lua.RUN_DIR / "Flows from Noël"
folder.mkdir(parents=True, exist_ok=True)
shutil.copyfile(REPO / "tests" / "data" / "fixture-full-score.musicxml",
                folder / "Noël - Full score - 01 Noël.musicxml")
try:
    code, result, _ = run_lua.run(REPO / "spike" / "50_paths.lua", open_file=harness.FIXTURE, timeout=600)
    facts = (result or {}).get("facts") or {}
    print("exit", code, "error", (result or {}).get("error"))
    print(json.dumps({k: facts.get(k) for k in ("listed", "utf8", "cp1252", "asListed")}, indent=1))
finally:
    shutil.rmtree(folder)
