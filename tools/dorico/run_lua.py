"""Run a Lua script inside Dorico and report the result it writes.

    python tools/dorico/run_lua.py SCRIPT [--open FILE] [--keep-open] [--args JSON] [--timeout 120]

The script reports through spike/lib/probe.lua, which writes %TEMP%/hbuc-run/result.json. Dorico runs it through a
launcher written for the one run, which names that run's args file: a script Dorico gets to late, after the runner
gave up on it, reads its own args and runId, never a later run's.
With --open, FILE is copied into the run directory and the copy is opened first. The probe checks
that the active project really is that copy before doing anything (probe.lua, args.expectScratch);
the runner closes it without saving afterwards only when the probe confirmed it (unless --keep-open).
Without --open the script runs on whatever project is active, which needs an explicit --on-active.
Exit codes: 0 ok, 1 checks failed, 2 timeout, refusal or connection failure, 3 bad --args or an error in the
runner itself.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import traceback
import uuid
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dws  # noqa: E402



def run_dir_for(env):
    """<temp>/hbuc-run, finding the temp folder as spike/lib/rundir.lua does (the launcher tells the Lua side anyway)."""
    temp = env.get("TEMP") or env.get("TMP") or env.get("TMPDIR") or "/tmp"
    return Path(temp) / "hbuc-run"


RUN_DIR = run_dir_for(os.environ)
REPO = Path(__file__).resolve().parents[2]
PRESS = Path(__file__).resolve().parent / "press.ps1"
TITLES = Path(__file__).resolve().parent / "titles.ps1"
# Prompts Dorico raises when opening a scratch copy, and the key that answers each safely.
# Matched by exact window title only; anything else is left alone and the run times out.
KNOWN_PROMPTS = {"Activate Project for Playback": "{ESC}"}  # Esc = "Do Not Activate"


LUAC_CANDIDATES = ["luac52", "luac5.2", "C:/ProgramData/chocolatey/lib/lua52/tools/luac52.exe", "luac"]


def find_luac():
    for c in LUAC_CANDIDATES:
        found = shutil.which(c) or (c if os.path.isfile(c) else None)
        if found:
            return found
    return None


def lua_files_for(script: Path):
    """The script plus every module it can require: its folder, its lib/, spike/lib/, fixtures/, the in-Dorico
    test library and the whole plug-in."""
    script = Path(script).resolve()
    folders = [script.parent, script.parent / "lib", REPO / "spike" / "lib", REPO / "fixtures",
               REPO / "tests" / "dorico" / "lib"]
    files, seen = [script], {script}
    plugin = REPO / "plugin"
    listed = [sorted(folder.glob("*.lua")) if folder.is_dir() else [] for folder in folders]
    listed.append(sorted(plugin.rglob("*.lua")) if plugin.is_dir() else [])
    for group in listed:
        for f in group:
            f = f.resolve()
            if f not in seen:
                seen.add(f)
                files.append(f)
    return files


def syntax_error(script: Path):
    """luac's message for the first file that does not compile, else None.
    Dorico skips a script with a syntax error silently, and a broken module kills it before probe.run."""
    luac = find_luac()
    if not luac:
        return None
    for f in lua_files_for(script):
        proc = subprocess.run([luac, "-p", str(f)], capture_output=True, text=True)
        if proc.returncode != 0:
            return (proc.stderr or proc.stdout).strip()
    return None


def window_titles():
    """The titles of Dorico's visible windows (capture.ps1 -All lists one per line: path, size, title)."""
    out = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(PRESS.parent / "capture.ps1"),
                          "-All", "-Out", str(RUN_DIR / "windows.png")], capture_output=True, text=True).stdout
    return [line.split("\t")[2] for line in out.splitlines() if line.count("\t") >= 2]


def open_windows():
    """The titles of the visible windows Dorico and PowerShell (the plug-in's dialog) have open, read through Win32,
    which doesn't wait on a busy Dorico as capture.ps1 does. [] off Windows, or if the lookup fails."""
    if os.name != "nt":
        return []
    try:
        out = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(TITLES)],
                             capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.TimeoutExpired):
        return []
    return [line.strip() for line in out.splitlines() if line.strip()]


def answer_known_prompts():
    for title, keys in KNOWN_PROMPTS.items():
        subprocess.run(
            ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(PRESS), "-Title", title, "-Keys", keys],
            capture_output=True,
        )


def fwd(path: Path) -> str:
    return str(path.resolve()).replace("\\", "/")


def wait_for(predicate, timeout, interval=0.5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(interval)
    return None


def open_scratch(client, source: Path):
    """Open a copy of source; returns (OpenScoreID, scratch path). The id is only a candidate: the probe
    confirms the active project is this copy before anything is changed or closed."""
    before = client.status().get("activeOpenScoreID")
    scratch = RUN_DIR / ("scratch" + source.suffix)
    shutil.copyfile(source, scratch)
    client.command(f"File.Open?File={fwd(scratch)}")

    def opened():
        st = client.status()
        sid = st.get("activeOpenScoreID")
        if st.get("hasScore") and sid is not None and sid != before:
            return (sid,)
        answer_known_prompts()
        return None

    got = wait_for(opened, 60, interval=1)
    if not got:
        raise TimeoutError(f"{source.name} did not open within 60s — Dorico may be showing a dialog")
    # The id appears before Dorico has finished with the project: a script run at once found the text export
    # writing nothing on a large one (Steinberg's Smith example).
    client.settle()
    return got[0], scratch


def scratch_open():
    return any(t.rstrip("*").endswith(" in scratch") for t in window_titles())


def close_scratch(client, score_id: int, attempts=5):
    """Close without saving, and confirm the copy's window has gone: Dorico can ignore a close that arrives
    while it is still finishing the script run."""
    for _ in range(attempts):
        client.command(f"File.CloseProject?OpenScoreID={score_id}&Save=false")
        time.sleep(1)
        if not scratch_open():
            return True
        time.sleep(2)
    print("the scratch copy could not be closed; close it in Dorico without saving", file=sys.stderr)
    return False


def read_result(run_id, problems=None):
    """This run's result, or None. problems, a list, gets what is wrong with a result.json that is there."""
    path = RUN_DIR / "result.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    except (OSError, ValueError) as e:
        if problems is not None:
            problems[:] = [f"result.json could not be read: {e}"]
        return None
    if data.get("runId") != run_id:
        if problems is not None:
            problems[:] = [f"result.json is another run's (runId {data.get('runId')})"]
        return None
    return data


def write_launcher(script: Path, args: dict, run_id: str) -> Path:
    """The script Dorico is asked to run: it names this run's args file for the probe (spike/lib/probe.lua), runs
    the script, and forgets the run again, since Dorico keeps one Lua state for every run."""
    for old in list(RUN_DIR.glob("launch-*.lua")) + list(RUN_DIR.glob("args-*.json")):
        old.unlink(missing_ok=True)  # a late run of an earlier launcher then finds nothing to run
    args_path = RUN_DIR / f"args-{run_id}.json"
    args_path.write_text(json.dumps(args), encoding="utf-8")
    launcher = RUN_DIR / f"launch-{run_id}.lua"
    launcher.write_text(
        "-- Written by tools/dorico/run_lua.py for one run.\n"
        f"HBUC_RUN = {{ dir = [==[{fwd(RUN_DIR)}/]==], args = [==[{fwd(args_path)}]==] }}\n"
        f"local ok, err = pcall(function() assert(loadfile([==[{fwd(script)}]==]))() end)\n"
        "HBUC_RUN = nil\n"
        "if not ok then error(err, 0) end\n",
        encoding="utf-8")
    return launcher


def run(script: Path, open_file=None, keep_open=False, extra_args=None, timeout=120, client=None, on_active=False):
    """Run one script; returns (exit_code, result_or_None, scratch_score_id_or_None)."""
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    if not open_file and not on_active:
        print("refusing to run on the active project without --on-active (use --open FILE for a scratch copy)", file=sys.stderr)
        return 2, None, None
    if open_file and scratch_open():
        print("a scratch copy from an earlier run is still open; close it in Dorico without saving first", file=sys.stderr)
        return 2, None, None
    err = syntax_error(script)
    if err:
        print(f"syntax error, not sent to Dorico: {err}", file=sys.stderr)
        return 2, None, None
    run_id = uuid.uuid4().hex
    args = dict(extra_args or {})
    args["runId"] = run_id
    try:
        (RUN_DIR / "result.json").unlink()
    except FileNotFoundError:
        pass

    own_client = client is None
    if own_client:
        client = dws.DoricoClient()
        client.connect()
    scratch_id = None
    verified = False
    try:
        if open_file:
            scratch_id, scratch = open_scratch(client, Path(open_file))
            # a .dorico copy is identified by its path; a MusicXML import is untitled (empty path)
            args["expectScratch"] = {"path": fwd(scratch) if scratch.suffix.lower() == ".dorico" else ""}
        launcher = write_launcher(Path(script).resolve(), args, run_id)
        client.command(f"Script.RunScript?ScriptPath={fwd(launcher)}&ShowConsole=false")
        problems = []
        result = wait_for(lambda: read_result(run_id, problems), timeout)
        if result is None:
            titles = open_windows()
            seen = "; windows open: " + ", ".join(repr(t) for t in titles) if titles else ""
            print(f"timed out after {timeout}s waiting for result" + "".join("; " + p for p in problems) + seen
                  + " — Dorico may be showing a dialog", file=sys.stderr)
            if scratch_id is not None:
                print("the scratch copy was not closed; close it in Dorico without saving", file=sys.stderr)
            return 2, None, scratch_id
        facts = result.get("facts") or {}
        verified = bool(facts.get("scratchVerified"))
        # The id seen while opening is a guess; the probe reports the verified copy's own id.
        if scratch_id is not None and verified and isinstance(facts.get("scratchScoreID"), int):
            scratch_id = facts["scratchScoreID"]
        if scratch_id is not None and not verified:
            print("the active project could not be confirmed as the scratch copy; nothing was closed", file=sys.stderr)
            return 2, result, scratch_id
        return (0 if result.get("ok") else 1), result, scratch_id
    finally:
        if scratch_id is not None and verified and not keep_open:
            close_scratch(client, scratch_id)
        if own_client:
            client.close()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("script")
    ap.add_argument("--open", dest="open_file")
    ap.add_argument("--keep-open", action="store_true")
    ap.add_argument("--on-active", action="store_true", help="run on the active project (no scratch copy)")
    ap.add_argument("--args", default="{}")
    ap.add_argument("--timeout", type=float, default=120)
    ns = ap.parse_args(argv)
    try:
        extra = json.loads(ns.args)
    except ValueError as e:
        print(f"--args is not JSON: {e}", file=sys.stderr)
        return 3
    try:
        code, result, scratch_id = run(Path(ns.script), ns.open_file, ns.keep_open, extra, ns.timeout,
                                       on_active=ns.on_active)
    except (OSError, ConnectionError, TimeoutError, EOFError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    except Exception:  # noqa: BLE001 - told apart from failed checks (1)
        traceback.print_exc()
        return 3
    if result is not None:
        print(json.dumps(result, indent=1, ensure_ascii=False))
    if scratch_id is not None and ns.keep_open:
        print(f"scratch project left open: OpenScoreID={scratch_id}", file=sys.stderr)
    return code


if __name__ == "__main__":
    sys.exit(main())
