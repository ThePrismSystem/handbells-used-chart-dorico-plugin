"""Run the project's tests.

    python tools/run_tests.py            unit tests: Python (unittest) and stock Lua 5.2
    python tools/run_tests.py --dorico   also the in-Dorico checks (needs Dorico running with remote control)
"""
import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "dorico"))
sys.path.insert(0, str(ROOT / "fixtures"))
import run_lua  # noqa: E402

PY_TESTS = ["tools/dorico/test_dws.py", "tools/dorico/test_run_lua.py", "fixtures/test_make_fixture_xml.py",
            "tools/test_install.py", "tools/test_package.py", "tests/dialog/test_mac_script.py",
            "tools/test_run_tests.py"]
LUA_TESTS = ["tests/run.lua", "spike/lib/test_json.lua", "spike/lib/test_events.lua"]
LUA_CANDIDATES = ["lua52", "lua5.2", "C:/ProgramData/chocolatey/lib/lua52/tools/lua52.exe", "lua"]


def lua_version(exe):
    """The interpreter's _VERSION, such as "Lua 5.2", or None if it won't run."""
    try:
        return subprocess.run([exe, "-e", "io.write(_VERSION)"], capture_output=True, text=True,
                              timeout=30).stdout.strip() or None
    except (OSError, subprocess.TimeoutExpired):
        return None


def find_lua():
    """Lua 5.2, the plug-in's language. A plain "lua" may be 5.3 or 5.4, whose integers and libraries differ."""
    import shutil
    import os
    for c in LUA_CANDIDATES:
        found = shutil.which(c) or (c if os.path.isfile(c) else None)
        if found and lua_version(found) == "Lua 5.2":
            return found
    return None


def step(name, ok):
    print(f"{'PASS' if ok else 'FAIL'}  {name}")
    return ok


def dorico_checks():
    import fixture_data
    import make_fixture_xml
    ok = True
    code, _, _ = run_lua.run(ROOT / "spike" / "00_smoke.lua", on_active=True)  # read-only
    ok &= step("dorico: smoke", code == 0)
    make_fixture_xml.main()
    args = {"headsPath": str((make_fixture_xml.BUILD / "heads.json").resolve()), "expected": fixture_data.EXPECTED}
    code, result, _ = run_lua.run(ROOT / "fixtures" / "verify_fixture.lua", open_file=ROOT / "fixtures" / "handbells-fixture.dorico",
                                  extra_args=args)
    if result and code != 0:
        for c in result.get("checks", []):
            if not c["ok"]:
                print("      ", c["label"], c.get("detail"))
    ok &= step("dorico: fixture verifies", code == 0)
    # The dialog on its own (a Windows desktop, no Dorico), then the plug-in's in-Dorico suites, each on its own
    # scratch copies.
    suites = sorted((ROOT / "tests" / "dialog").glob("test_*.py")) + sorted((ROOT / "tests" / "dorico").glob("test_*.py"))
    for suite in suites:
        proc = subprocess.run([sys.executable, str(suite)], cwd=ROOT, capture_output=True, text=True)
        last = proc.stderr.strip().splitlines()[-1] if proc.stderr.strip() else ""
        ok &= step(f"dorico: {suite.name} ({last})", proc.returncode == 0)
        if proc.returncode != 0:
            # the first failure is usually the cause, and later ones its knock-on effects
            first = proc.stderr.find("\n=====")
            print(proc.stderr[max(first, 0):max(first, 0) + 3000])
            print("...")
            print(proc.stderr[-1500:])
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dorico", action="store_true")
    ns = ap.parse_args()
    ok = True
    proc = subprocess.run([sys.executable, "-m", "unittest", *PY_TESTS], cwd=ROOT, capture_output=True, text=True)
    ok &= step(f"python unit tests ({proc.stderr.strip().splitlines()[-1] if proc.stderr.strip() else ''})", proc.returncode == 0)
    if proc.returncode != 0:
        print(proc.stderr[-3000:])
    lua = find_lua()
    if not lua:
        ok &= step("stock Lua 5.2 found", False)
    else:
        for t in LUA_TESTS:
            proc = subprocess.run([lua, t], cwd=ROOT, capture_output=True, text=True)
            ok &= step(f"lua {t}", proc.returncode == 0)
            if proc.returncode != 0:
                print(proc.stdout[-2000:], proc.stderr[-2000:])
    if ns.dorico:
        ok &= dorico_checks()
    print("ALL PASS" if ok else "SOME FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
