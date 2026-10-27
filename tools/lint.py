"""Run the project's linters and security scanners over the files git tracks.

    python tools/lint.py                    every tool that is installed; a missing one is skipped
    python tools/lint.py --only ruff,eslint just those
    python tools/lint.py --codeql           also CodeQL, which takes a few minutes
    python tools/lint.py --strict           a missing tool fails the run (CI uses this)
    python tools/lint.py --sarif DIR        the security tools also write SARIF files to DIR

Only files in git's index are checked. A new file is left out until you git add it, and ignored or excluded files
are always left out.
"""
import argparse
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Tool:
    name: str
    exe: str
    install: str
    # run(exe, sarif_dir) prints the tool's findings and returns True when there are none
    run: Callable[[str, "Path | None"], bool]
    optional: bool = False


def tracked(patterns, cwd=ROOT):
    """The tracked files matching any of the patterns, as repo-relative POSIX paths, sorted."""
    out = subprocess.run(["git", "ls-files", "-z", "--", *patterns], cwd=cwd, capture_output=True, check=True).stdout
    return sorted(p for p in out.decode("utf-8").split("\0") if p)


def find_exe(name):
    """Looks in the project's node_modules/.bin (where npm puts ESLint) before the PATH."""
    return shutil.which(name, path=str(ROOT / "node_modules" / ".bin")) or shutil.which(name)


def run_tool(tool, strict, sarif_dir):
    exe = find_exe(tool.exe)
    if not exe:
        status = "FAIL" if strict else "SKIP"
        print(f"{status}  {tool.name}: {tool.exe} not found. {tool.install}")
        return status
    sys.stdout.flush()
    status = "PASS" if tool.run(exe, sarif_dir) else "FAIL"
    print(f"{status}  {tool.name}")
    return status


def ruff(exe, sarif_dir):
    return subprocess.run([exe, "check", "--no-fix", *tracked(["*.py"])], cwd=ROOT).returncode == 0


TOOLS = [
    Tool("ruff", "ruff", "pip install -r requirements-dev.txt", ruff),
]


def main(argv=None):
    ap = argparse.ArgumentParser(description="Run the linters and security scanners.")
    ap.add_argument("--strict", action="store_true", help="a tool that isn't installed fails the run")
    ap.add_argument("--sarif", metavar="DIR", help="where the security tools write SARIF")
    ap.add_argument("--codeql", action="store_true", help="also run CodeQL (slow)")
    ap.add_argument("--only", metavar="NAMES", help="comma-separated tool names")
    ns = ap.parse_args(argv)
    if ns.only:
        names = ns.only.split(",")
        unknown = set(names) - {t.name for t in TOOLS}
        if unknown:
            ap.error("unknown tool: " + ", ".join(sorted(unknown)))
        tools = [t for t in TOOLS if t.name in names]
    else:
        tools = [t for t in TOOLS if ns.codeql or not t.optional]
    sarif_dir = Path(ns.sarif).resolve() if ns.sarif else None
    if sarif_dir:
        sarif_dir.mkdir(parents=True, exist_ok=True)
    results = [run_tool(t, ns.strict, sarif_dir) for t in tools]
    skipped = results.count("SKIP")
    if "FAIL" in results:
        print("SOME FAILED")
        return 1
    print("ALL PASS" + (f" ({skipped} skipped)" if skipped else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
