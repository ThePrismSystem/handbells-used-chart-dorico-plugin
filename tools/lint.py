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
import json
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Tool:
    name: str
    exe: "str | tuple[str, ...]"  # the first of several that is installed
    install: str
    # run(exe, sarif_dir) prints the tool's findings and returns True when there are none
    run: Callable[[str, "Path | None"], bool]
    optional: bool = False


def tracked(patterns, cwd=ROOT):
    """The tracked files matching any of the patterns, as repo-relative POSIX paths, sorted."""
    out = subprocess.run(["git", "ls-files", "-z", "--", *patterns], cwd=cwd, capture_output=True, check=True).stdout
    return sorted(p for p in out.decode("utf-8").split("\0") if p)


def copy_tracked(dest, cwd=ROOT):
    """Copies each tracked file as it is in the working tree: uncommitted edits are scanned, untracked files never."""
    for rel in tracked([], cwd=cwd):
        source = Path(cwd) / rel
        if source.is_file():  # not deleted in the working tree
            target = Path(dest) / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)


def find_exe(name):
    """Looks in the project's node_modules/.bin (where npm puts ESLint) before the PATH."""
    return shutil.which(name, path=str(ROOT / "node_modules" / ".bin")) or shutil.which(name)


def run_tool(tool, strict, sarif_dir):
    names = (tool.exe,) if isinstance(tool.exe, str) else tool.exe
    exe = next((found for found in map(find_exe, names) if found), None)
    if not exe:
        status = "FAIL" if strict else "SKIP"
        print(f"{status}  {tool.name}: {' or '.join(names)} not found. {tool.install}")
        return status
    sys.stdout.flush()
    status = "PASS" if tool.run(exe, sarif_dir) else "FAIL"
    print(f"{status}  {tool.name}")
    return status


def ruff(exe, sarif_dir):
    return subprocess.run([exe, "check", "--no-fix", *tracked(["*.py"])], cwd=ROOT).returncode == 0


def luacheck(exe, sarif_dir):
    argv = [exe, "--config", str(ROOT / ".luacheckrc"), "--codes", "--quiet", *tracked(["*.lua"])]
    return subprocess.run(argv, cwd=ROOT).returncode == 0


def eslint(exe, sarif_dir):
    return subprocess.run([exe, "--max-warnings", "0", *tracked(["*.js"])], cwd=ROOT).returncode == 0


def zizmor(exe, sarif_dir):
    """The workflows and Dependabot's config. With GH_TOKEN set, zizmor also runs its online audits."""
    files = tracked([".github/workflows/*.yml", ".github/dependabot.yml"])
    clean = subprocess.run([exe, *files], cwd=ROOT).returncode == 0
    if sarif_dir:
        proc = subprocess.run([exe, "--format", "sarif", *files], cwd=ROOT, capture_output=True, text=True)
        (sarif_dir / "zizmor.sarif").write_text(proc.stdout, encoding="utf-8")
    return clean


def gitleaks(exe, sarif_dir):
    argv = [exe, "git", "--redact", "--no-banner", "--exit-code", "1"]
    if sarif_dir:
        argv += ["--report-format", "sarif", "--report-path", str(sarif_dir / "gitleaks.sarif")]
    return subprocess.run([*argv, str(ROOT)], cwd=ROOT).returncode == 0


# Each language, and the folder its database gets in a cluster.
CODEQL_LANGUAGES = {"actions": "actions", "javascript-typescript": "javascript", "python": "python"}


def codeql(exe, sarif_dir):
    """The queries code scanning runs (.github/codeql/codeql-config.yml), over a copy of the tracked files."""
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        source, db = tmp / "source", tmp / "db"
        copy_tracked(source)
        create = [exe, "database", "create", str(db), "--db-cluster", "--language=" + ",".join(CODEQL_LANGUAGES),
                  "--build-mode=none", "--source-root", str(source),
                  "--codescanning-config=" + str(ROOT / ".github" / "codeql" / "codeql-config.yml"), "--overwrite"]
        if subprocess.run(create, cwd=ROOT).returncode != 0:
            return False
        found = 0
        for folder in CODEQL_LANGUAGES.values():
            out = tmp / f"{folder}.sarif"
            analyze = [exe, "database", "analyze", str(db / folder), "--format=sarif-latest", "--output", str(out)]
            if subprocess.run(analyze, cwd=ROOT).returncode != 0:
                return False
            sarif = json.loads(out.read_text(encoding="utf-8"))
            for run in sarif.get("runs", []):
                for r in run.get("results", []):
                    where = (r.get("locations") or [{}])[0].get("physicalLocation", {})
                    print(f"{where.get('artifactLocation', {}).get('uri')}:{where.get('region', {}).get('startLine')} "
                          f"{r.get('ruleId')} {r.get('message', {}).get('text')}")
            found += sarif_result_count(sarif)
    return found == 0


def sarif_result_count(sarif):
    return sum(len(run.get("results", [])) for run in sarif.get("runs", []))


def write_sarif(sarif_dir, name, sarif):
    (sarif_dir / f"{name}.sarif").write_text(json.dumps(sarif, indent=1), encoding="utf-8")


def parse_pssa_json(text):
    """PSScriptAnalyzer's records from ConvertTo-Json, which gives one object rather than a list of one."""
    data = json.loads(text) if text.strip() else []
    return data if isinstance(data, list) else [data]


PSSA_LEVELS = {0: "note", 1: "warning", 2: "error", 3: "error",
               "Information": "note", "Warning": "warning", "Error": "error", "ParseError": "error"}


def repo_path(path, root):
    try:
        return Path(path).resolve().relative_to(Path(root).resolve()).as_posix()
    except ValueError:
        return Path(path).as_posix()


def pssa_to_sarif(records, root):
    results = [{
        "ruleId": r["RuleName"],
        "level": PSSA_LEVELS.get(r.get("Severity"), "warning"),
        "message": {"text": r.get("Message") or r["RuleName"]},
        "locations": [{"physicalLocation": {
            "artifactLocation": {"uri": repo_path(r["ScriptPath"], root)},
            "region": {"startLine": r.get("Line") or 1, "startColumn": r.get("Column") or 1}}}],
    } for r in records]
    rules = [{"id": rule} for rule in sorted({r["RuleName"] for r in records})]
    return {"version": "2.1.0", "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
            "runs": [{"tool": {"driver": {"name": "PSScriptAnalyzer",
                                          "informationUri": "https://github.com/PowerShell/PSScriptAnalyzer",
                                          "rules": rules}},
                      "results": results}]}


def psscriptanalyzer(exe, sarif_dir):
    argv = [exe, "-NoProfile", "-NonInteractive", "-File", str(ROOT / "tools" / "pssa.ps1"),
            "-Settings", str(ROOT / "PSScriptAnalyzerSettings.psd1"), *tracked(["*.ps1"])]
    proc = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True)
    if proc.returncode != 0:
        print(proc.stdout, proc.stderr, sep="\n")
        return False
    records = parse_pssa_json(proc.stdout)
    for r in records:
        print(f"{repo_path(r['ScriptPath'], ROOT)}:{r.get('Line')}:{r.get('Column')} {r['RuleName']} {r.get('Message')}")
    if sarif_dir:
        write_sarif(sarif_dir, "psscriptanalyzer", pssa_to_sarif(records, ROOT))
    return not records


TOOLS = [
    Tool("ruff", "ruff", "pip install -r requirements-dev.txt", ruff),
    Tool("luacheck", "luacheck", "luarocks install luacheck 1.2.0", luacheck),
    Tool("psscriptanalyzer", ("pwsh", "powershell"),
         "Install-Module PSScriptAnalyzer, InjectionHunter -Scope CurrentUser (the versions are in lint.yml)",
         psscriptanalyzer),
    Tool("eslint", "eslint", "npm ci", eslint),
    Tool("zizmor", "zizmor", "pip install -r requirements-dev.txt", zizmor),
    Tool("gitleaks", "gitleaks", "Get it from https://github.com/gitleaks/gitleaks/releases (lint.yml has the version).",
         gitleaks),
    Tool("codeql", "codeql", "Get the CodeQL bundle from https://github.com/github/codeql-action/releases.", codeql,
         optional=True),
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
