"""Build the release zip: the plug-in and its documents in one versioned folder.

    python tools/package.py [--out DIR]
    python tools/package.py --tag v0.1.0 --notes notes.md --outputs "$GITHUB_OUTPUT"   what the release workflow runs

Writes dist/handbells-used-chart-dorico-v<version>.zip, with the version read from hbuc/constants.lua. Inside,
handbells-used-chart-dorico-v<version>/ holds the menu file, its folder, README.md, LICENSE.md and CHANGELOG.md:
the menu file and the folder go into Dorico's Script Plug-ins folder (README.md says where). Text files get Unix
line endings, so the zip is the same whichever way git checked them out.
"""
import argparse
import hashlib
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
REPO = "ThePrismSystem/handbells-used-chart-dorico-plugin"


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


def tag_kind(tag, version):
    """"release" for v<version>, "candidate" for v<version>-rc.<N>, and None for any other tag."""
    if tag == f"v{version}":
        return "release"
    if re.fullmatch(rf"v{re.escape(version)}-rc\.(0|[1-9][0-9]*)", tag):
        return "candidate"
    return None


def release_notes(changelog, version, zip_name, sha256):
    """The CHANGELOG section for the version, then the zip's checksum and how to check where it came from."""
    section = re.search(rf"^## \[{re.escape(version)}\][^\n]*\n(.*?)(?=^## \[|^\[[^\]]+\]: |\Z)", changelog,
                        re.M | re.S)
    if not section:
        raise ValueError(f"CHANGELOG.md has no section for {version}")
    return (f"{section.group(1).strip()}\n\n"
            f"SHA-256: {sha256}\n\n"
            "To check that this zip was built from this repository by its release workflow, run:\n\n"
            f"    gh attestation verify {zip_name} --repo {REPO} --signer-workflow {REPO}/.github/workflows/release.yml\n")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", help="the folder to write the zip to (default: dist/)")
    ap.add_argument("--tag", help="the release tag, which must be v<version> or v<version>-rc.<N>")
    ap.add_argument("--notes", help="with --tag: where to write the release notes")
    ap.add_argument("--outputs", help="with --tag: a file to add zip=<path> and prerelease=<true|false> to")
    ns = ap.parse_args(argv)
    kind = tag_kind(ns.tag, version()) if ns.tag else None
    if ns.tag and not kind:
        print(f"tag {ns.tag} does not match version {version()}", file=sys.stderr)
        return 1
    path = build(ns.out)
    print(f"wrote {path}")
    if ns.tag and ns.notes:
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
        Path(ns.notes).write_text(release_notes(changelog, version(), path.name, digest), encoding="utf-8")
    if ns.tag and ns.outputs:
        with open(ns.outputs, "a", encoding="utf-8") as f:
            f.write(f"zip={path}\nprerelease={'true' if kind == 'candidate' else 'false'}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
