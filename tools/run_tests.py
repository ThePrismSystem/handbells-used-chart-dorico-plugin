"""Run the project's tests.

    python tools/run_tests.py              unit tests: Python (unittest) and stock Lua 5.2
    python tools/run_tests.py --coverage   the same, measured: reports go to coverage/ (luacov, coverage.py, c8)
    python tools/run_tests.py --dorico     also the in-Dorico checks (needs Dorico running with remote control)
"""
import argparse
import importlib.util
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "dorico"))
sys.path.insert(0, str(ROOT / "fixtures"))
import run_lua  # noqa: E402

PY_TESTS = ["tools/dorico/test_dws.py", "tools/dorico/test_run_lua.py", "fixtures/test_make_fixture_xml.py",
            "tools/test_install.py", "tools/test_package.py", "tests/dialog/test_mac_script.py",
            "tests/dialog/test_launch.py", "tests/dialog/test_mac_coverage.py", "tests/dialog/test_mac_drive.py",
            "tools/test_run_tests.py", "tools/test_lint.py",
            "tests/test_shipped_calls.py"]
LUA_TESTS = ["tests/run.lua", "spike/lib/test_json.lua", "spike/lib/test_events.lua"]
LUA_CANDIDATES = ["lua52", "lua5.2", "C:/ProgramData/chocolatey/lib/lua52/tools/lua52.exe", "lua"]
COVERAGE_DIR = ROOT / "coverage"
MEASURED_LUA = "tests/run.lua"  # the plug-in's tests; the spike's libraries aren't part of the plug-in
LUACOV_REPORT = "require('luacov.reporter.lcov').report()"  # with .luacov's settings


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


def c8():
    """c8 as npm ci installs it, or None."""
    return shutil.which("c8", path=str(ROOT / "node_modules" / ".bin"))


def coverage_tools(lua):
    """How to install each coverage tool that is missing: an empty list when they're all there."""
    hints = []
    probe = "require('luacov.runner'); require('luacov.reporter.lcov')"
    if not lua or subprocess.run([lua, "-e", probe], capture_output=True).returncode != 0:
        hints.append("luarocks install luacov && luarocks install cluacov && luarocks install luacov-reporter-lcov")
    if importlib.util.find_spec("coverage") is None:
        hints.append("pip install -r requirements-dev.txt (coverage.py)")
    if not c8():
        hints.append("npm ci (c8)")
    return hints


def lcov_percent(path):
    """Lines hit over lines found, as a percentage, or None when there is no report."""
    if not path.exists():
        return None
    found = hit = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("LF:"):
            found += int(line[3:])
        elif line.startswith("LH:"):
            hit += int(line[3:])
    return 100.0 * hit / found if found else 0.0


def normalize_lcov(path):
    """Source paths relative to the repository: tests/run.lua finds the plug-in through tests/../."""
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    out = [("SF:" + Path(os.path.normpath(line[3:].rstrip("\n"))).as_posix() + "\n") if line.startswith("SF:") else line
           for line in lines]
    path.write_text("".join(out), encoding="utf-8")


def coverage_reports(lua):
    """coverage/lua.lcov, coverage/python.xml and coverage/js-node/lcov.info, then each language's total."""
    ok = True
    reports = [
        ("lua", [lua, "-e", LUACOV_REPORT]),
        ("python", [sys.executable, "-m", "coverage", "xml", "-o", str(COVERAGE_DIR / "python.xml")]),
        ("javascript", [c8(), "report", "--temp-directory", str(COVERAGE_DIR / "v8"), "--include", "plugin/**",
                        "--reporter", "lcovonly", "--reports-dir", str(COVERAGE_DIR / "js-node")]),
    ]
    for name, argv in reports:
        proc = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True)
        ok &= step(f"coverage report: {name}", proc.returncode == 0)
        if proc.returncode != 0:
            print(proc.stdout[-2000:], proc.stderr[-2000:])
    lua_report = COVERAGE_DIR / "lua.lcov"
    if lua_report.exists():
        normalize_lcov(lua_report)
    python = subprocess.run([sys.executable, "-m", "coverage", "report", "--format=total"], cwd=ROOT,
                            capture_output=True, text=True).stdout.strip()

    def percent(value):
        return "no report" if value is None else f"{value:.1f}%"
    print(f"      lua {percent(lcov_percent(lua_report))}, python {python}%, "
          f"javascript run by Node {percent(lcov_percent(COVERAGE_DIR / 'js-node' / 'lcov.info'))}")
    return ok


def dorico_checks():  # pragma: no cover - drives Dorico through its Remote Control API
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


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--dorico", action="store_true")
    ap.add_argument("--coverage", action="store_true")
    ns = ap.parse_args(argv)
    lua = find_lua()
    python = [sys.executable, "-m", "unittest", *PY_TESTS]
    env = None
    if ns.coverage:
        hints = coverage_tools(lua)
        if hints:
            print("--coverage needs:\n  " + "\n  ".join(hints))
            return 1
        # luacov adds to its stats file rather than replacing it
        shutil.rmtree(COVERAGE_DIR, ignore_errors=True)
        COVERAGE_DIR.mkdir(parents=True)
        python = [sys.executable, "-m", "coverage", "run", "-m", "unittest", *PY_TESTS]
        # the Mac script's tests run it under Node, which then records what ran for c8
        env = {**os.environ, "NODE_V8_COVERAGE": str(COVERAGE_DIR / "v8")}
    ok = True
    proc = subprocess.run(python, cwd=ROOT, capture_output=True, text=True, env=env)
    ok &= step(f"python unit tests ({proc.stderr.strip().splitlines()[-1] if proc.stderr.strip() else ''})", proc.returncode == 0)
    if proc.returncode != 0:
        print(proc.stderr[-3000:])
    if not lua:
        ok &= step("stock Lua 5.2 found", False)
    else:
        for t in LUA_TESTS:
            measured = ns.coverage and t == MEASURED_LUA
            proc = subprocess.run([lua, "-lluacov", t] if measured else [lua, t], cwd=ROOT, capture_output=True,
                                  text=True)
            ok &= step(f"lua {t}", proc.returncode == 0)
            if proc.returncode != 0:
                print(proc.stdout[-2000:], proc.stderr[-2000:])
    if ns.coverage:
        ok &= coverage_reports(lua)
    if ns.dorico:
        ok &= dorico_checks()
    print("ALL PASS" if ok else "SOME FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
