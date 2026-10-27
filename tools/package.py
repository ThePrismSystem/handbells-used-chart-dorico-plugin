"""Build the release zip: the plug-in and its documents in one versioned folder.

    python tools/package.py [--out DIR]

Writes dist/handbells-used-chart-dorico-v<version>.zip, with the version read from hbuc/constants.lua. Inside,
handbells-used-chart-dorico-v<version>/ holds the menu file, its folder, README.md, LICENSE.md and CHANGELOG.md:
the menu file and the folder go into Dorico's Script Plug-ins folder (README.md says where). Text files get Unix
line endings, so the zip is the same whichever way git checked them out.
"""
import argparse
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "plugin"
ENTRY = "Handbells Used Chart.lua"
FOLDER = "Handbells Used Chart"
DOCUMENTS = ["README.md", "LICENSE.md", "CHANGELOG.md"]
CONSTANTS = PLUGIN / FOLDER / "hbuc" / "constants.lua"
TEXT = {".lua", ".js", ".ps1", ".md", ".json", ".txt"}
SKIP = {"__pycache__", ".DS_Store"}


def version(constants=CONSTANTS):
    found = re.search(r'^constants\.VERSION = "([^"]+)"', Path(constants).read_text(encoding="utf-8"), re.M)
    if not found:
        raise ValueError(f"no constants.VERSION in {constants}")
    return found.group(1)


def files():
    """(path on disk, path inside the versioned folder) for everything the zip holds."""
    yield PLUGIN / ENTRY, ENTRY
    for path in sorted((PLUGIN / FOLDER).rglob("*")):
        if path.is_file() and not SKIP.intersection(path.parts) and path.suffix != ".pyc":
            yield path, path.relative_to(PLUGIN).as_posix()
    for name in DOCUMENTS:
        yield ROOT / name, name


def build(out_dir=None):
    out_dir = Path(out_dir) if out_dir else ROOT / "dist"
    out_dir.mkdir(parents=True, exist_ok=True)
    top = f"handbells-used-chart-dorico-v{version()}"
    path = out_dir / f"{top}.zip"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for source, name in files():
            data = source.read_bytes()
            if source.suffix in TEXT:
                data = data.replace(b"\r\n", b"\n")
            z.writestr(f"{top}/{name}", data)
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", help="the folder to write the zip to (default: dist/)")
    print(f"wrote {build(ap.parse_args().out)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
