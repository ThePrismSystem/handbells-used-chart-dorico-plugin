"""How the dialog tests start the dialog scripts.

Windows (test_windows_dialog.py): with HBUC_PS_COVERAGE set to a folder, each run goes through covered.ps1, which runs
windows.ps1 inside Pester and writes a Cobertura report for that run into the folder.

Mac (test_mac_dialog.py): with HBUC_JS_COVERAGE set to a folder, osascript runs a copy of mac.js made by
instrument_mac.js, and each run writes its counts into the folder.
"""
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PS1 = ROOT / "plugin" / "Handbells Used Chart" / "dialog" / "windows.ps1"
MAC_JS = ROOT / "plugin" / "Handbells Used Chart" / "dialog" / "mac.js"
COVERED = Path(__file__).resolve().parent / "covered.ps1"
START = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File"]
OSASCRIPT = ["/usr/bin/osascript", "-l", "JavaScript"]


def report_name(suffix):
    # "coverage" in the name is what Codecov's uploader looks for
    return f"coverage-{uuid.uuid4().hex}{suffix}"


def command(args, env):
    """The command line that shows the dialog with windows.ps1's args, measured when env asks for it."""
    folder = env.get("HBUC_PS_COVERAGE")
    if not folder:
        return [*START, str(PS1), *args]
    return [*START, str(COVERED), "-Out", str(Path(folder) / report_name(".xml")), *args]


def mac_command(args, env, instrumented):
    """The command line and environment that show mac.js with these args: the instrumented copy, with a report of
    its own, when env asks for coverage."""
    folder = env.get("HBUC_JS_COVERAGE")
    if not folder:
        return [*OSASCRIPT, str(MAC_JS), *args], dict(env)
    return [*OSASCRIPT, str(instrumented), *args], {**env, "HBUC_COVERAGE": str(Path(folder) / report_name(".json"))}
