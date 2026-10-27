"""Scratch test inputs made from Dorico's example projects, which hold lyrics, slurs and several voices per staff.

    python tests/dorico/inputs.py        make any missing input

Each example is copied by tools/dorico/run_lua.py into the run folder and only the copy is opened; the copy is
saved over itself by spike/save_scratch.lua (after the probe confirms it is the active project), then kept as
%TEMP%/hbuc-run/inputs/<name>.dorico. The examples were saved by older Dorico versions, so opening a copy shows
the "created in an earlier version" notice, which is answered with Enter. The originals are never opened.
"""
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "dorico"))
import run_lua  # noqa: E402

EXAMPLES = Path("C:/Users/Public/Documents/Dorico Example Projects")
INPUTS = run_lua.RUN_DIR / "inputs"
SOURCES = {"smith": "Smith - Preces and Responses.dorico", "liszt": "Liszt - Liebestraume.dorico"}
TOOLS = ROOT / "tools" / "dorico"


def windows():
    out = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(TOOLS / "capture.ps1"),
                          "-All", "-Out", str(run_lua.RUN_DIR / "windows.png")], capture_output=True, text=True).stdout
    return [line.split("\t") for line in out.splitlines() if line.count("\t") >= 2]


def answer_notice(deadline):
    """Enter on the notice: a window titled exactly 'Dorico' that is wider than tall and is not a progress bar
    (the progress dialog is about 480 x 320 at this display's scale; the notice about 1150 x 320)."""
    while time.time() < deadline:
        for i, row in enumerate(windows()):
            w, _, h = row[1].partition(" x ")
            if row[2] == "Dorico" and w.isdigit() and int(w) > 900 and int(h or 0) < 500:
                subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(TOOLS / "press.ps1"),
                                "-Index", str(i), "-Keys", "{ENTER}"], capture_output=True)
                return True
        time.sleep(2)
    return False


def ensure(name):
    target = INPUTS / f"{name}.dorico"
    if target.exists():
        return target
    INPUTS.mkdir(parents=True, exist_ok=True)
    source = EXAMPLES / SOURCES[name]
    outcome = {}
    worker = threading.Thread(target=lambda: outcome.setdefault(
        "run", run_lua.run(ROOT / "spike" / "save_scratch.lua", open_file=source, timeout=180)))
    worker.start()
    answer_notice(time.time() + 120)
    worker.join()
    code = outcome["run"][0]
    if code != 0:
        raise RuntimeError(f"could not make the {name} input (runner exit {code})")
    shutil.copyfile(run_lua.RUN_DIR / "scratch.dorico", target)
    return target


if __name__ == "__main__":
    for n in SOURCES:
        print(ensure(n))
