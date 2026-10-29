"""Drive spike/46_export_dialog.lua: does Dorico's MusicXML export dialog open while a script runs, and does the
script carry on after it closes?

    python spike/46_export_dialog.py [PROJECT.dorico] [export|cancel]

On a scratch copy (default: the fixture) this runs the Lua spike in the background and watches Dorico's windows
through Win32. It notes when the script starts, when a new window appears, whether the run had already finished by
then, captures the window, presses Export or Cancel in it, and notes when the run finishes. Then it lists the
MusicXML files written since the start under the run folder and the user's Documents. The copy is closed unsaved.
Output: %TEMP%\\hbuc-run\\46\\ (timeline.json, dialog.png).
"""
import json
import os
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tests" / "dorico"))
import harness  # noqa: E402
import dws  # noqa: E402
import run_lua  # noqa: E402

SCRIPT = REPO / "spike" / "46_export_dialog.lua"
OUT = run_lua.RUN_DIR / "46"
IGNORED = ("Activate Project for Playback",)


def new_titles(before):
    return [t for t in run_lua.open_windows()
            if t not in before and t not in IGNORED and not t.rstrip("*").endswith(" in scratch")]


def musicxml_since(start, roots):
    found = []
    for root in roots:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if path.suffix.lower() in (".musicxml", ".mxl", ".xml") and path.stat().st_mtime >= start:
                found.append(f"{path} ({path.stat().st_size} bytes)")
    return found


def main():
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else harness.FIXTURE
    action = sys.argv[2] if len(sys.argv) > 2 else "export"
    OUT.mkdir(parents=True, exist_ok=True)
    started_file = run_lua.RUN_DIR / "46-started.txt"
    started_file.unlink(missing_ok=True)
    before = set(run_lua.open_windows())
    t0 = time.time()
    timeline = []

    def note(event):
        timeline.append([round(time.time() - t0, 1), event])
        print(f"{timeline[-1][0]:7.1f}s  {event}", flush=True)

    client = dws.DoricoClient()
    client.connect()
    run = harness.Background(lambda: run_lua.run(SCRIPT, open_file=source, keep_open=True, client=client,
                                                 timeout=600))
    dialog = None
    seen_start = False
    deadline = time.time() + 600
    while time.time() < deadline:
        if not seen_start and started_file.exists():
            seen_start = True
            note("the script started")
        if dialog is None:
            titles = new_titles(before)
            if titles:
                dialog = titles[0]
                note(f"new window {dialog!r}; run finished already: {not run.thread.is_alive()}")
                time.sleep(2)
                harness.capture_window(dialog, OUT / "dialog.png")
                note("captured dialog.png")
                buttons = ["Export", "Close", "Cancel"] if action == "export" else ["Cancel", "Close"]
                for button in buttons:
                    pressed = harness.click(dialog, button)
                    note(f"pressed {button}: {pressed}")
                    if pressed:
                        break
        if not run.thread.is_alive() and (dialog is not None or time.time() - t0 > 120):
            break
        time.sleep(0.5)
    code, result, _ = run.join(60) or (None, None, None)
    note(f"run finished: exit {code}")
    if dialog is None:
        time.sleep(5)
        late = new_titles(before)
        note(f"windows after the run: {late}")
    facts = (result or {}).get("facts") or {}
    note("facts: " + json.dumps({k: facts.get(k) for k in
                                 ("flowCount", "commandOk", "commandResult", "secondsInCommand", "scratchVerified")}))
    time.sleep(3)
    files = musicxml_since(t0 - 1, [run_lua.RUN_DIR, Path(os.environ["USERPROFILE"]) / "Documents"])
    note(f"MusicXML written: {files}")
    still = new_titles(before)
    if still:
        note(f"still open: {still}")
    (OUT / "timeline.json").write_text(json.dumps({"timeline": timeline, "result": result}, indent=1),
                                       encoding="utf-8")
    if facts.get("scratchVerified") and not still:
        note(f"closed the copy: {run_lua.close_scratch(client, facts['scratchScoreID'])}")
    client.close()


if __name__ == "__main__":
    main()
