r"""Install the plug-in into Dorico 6's Script Plug-ins folder, where it appears as Script > Handbells Used Chart.

    python tools/install.py [--target DIR] [--uninstall]

The folder is %APPDATA%\Steinberg\Dorico 6\Script Plug-ins on Windows, and
~/Library/Application Support/Steinberg/Dorico 6/Script Plug-ins on a Mac.

Copies plugin/Handbells Used Chart.lua (the menu entry) and plugin/Handbells Used Chart/ (its code and dialog).
Any earlier copy of exactly those two is removed first; nothing else in the folder is touched.
"""
import argparse
import os
import shutil
import sys
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "plugin"
ENTRY = "Handbells Used Chart.lua"
FOLDER = "Handbells Used Chart"


def default_target(env=None, platform=None):
    env = os.environ if env is None else env
    platform = sys.platform if platform is None else platform
    if platform == "darwin":
        home = env.get("HOME") or Path.home()
        return Path(home) / "Library" / "Application Support" / "Steinberg" / "Dorico 6" / "Script Plug-ins"
    return Path(env["APPDATA"]) / "Steinberg" / "Dorico 6" / "Script Plug-ins"


def uninstall(target):
    target = Path(target)
    if (target / ENTRY).is_file():
        (target / ENTRY).unlink()
    if (target / FOLDER).is_dir():
        shutil.rmtree(target / FOLDER)


def install(target):
    target = Path(target)
    target.mkdir(parents=True, exist_ok=True)
    uninstall(target)
    shutil.copy2(SOURCE / ENTRY, target / ENTRY)
    shutil.copytree(SOURCE / FOLDER, target / FOLDER, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    return target


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", help="the Script Plug-ins folder (default: Dorico 6's own)")
    ap.add_argument("--uninstall", action="store_true")
    ns = ap.parse_args()
    target = Path(ns.target) if ns.target else default_target()
    if ns.uninstall:
        uninstall(target)
        print(f"removed the plug-in from {target}")
    else:
        install(target)
        print(f"installed into {target}; it is in Dorico's Script menu as Handbells Used Chart")
    return 0


if __name__ == "__main__":
    sys.exit(main())
