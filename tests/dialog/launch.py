"""How tests/dialog/test_windows_dialog.py starts dialog/windows.ps1.

With HBUC_PS_COVERAGE set to a folder, each run goes through covered.ps1, which runs the dialog inside Pester and
writes a Cobertura report for that run into the folder.
"""
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PS1 = ROOT / "plugin" / "Handbells Used Chart" / "dialog" / "windows.ps1"
COVERED = Path(__file__).resolve().parent / "covered.ps1"
START = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File"]


def command(args, env):
    """The command line that shows the dialog with windows.ps1's args, measured when env asks for it."""
    folder = env.get("HBUC_PS_COVERAGE")
    if not folder:
        return [*START, str(PS1), *args]
    # "coverage" in the name is what Codecov's uploader looks for
    return [*START, str(COVERED), "-Out", str(Path(folder) / f"coverage-{uuid.uuid4().hex}.xml"), *args]
