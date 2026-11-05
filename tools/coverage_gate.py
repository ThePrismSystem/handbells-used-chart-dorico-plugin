"""Fails when a language's line coverage, merged over its reports, is under the floor.

    python tools/coverage_gate.py <language> <report or folder>...

A report is lcov (.info, .lcov) or Cobertura XML (.xml), and a folder stands for every report in it. A line counts as
covered when any report hit it. Codecov holds only the lines a pull request changes (codecov/patch): its per-language
checks need its Pro plan, so each CI job holds the languages it measures to the floor with this.
Exits 0 at or over the floor, 1 under it, and 2 when there is nothing to measure.
"""
import argparse
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

FLOOR = 80  # percent of each language's lines
REPORTS = {".info", ".lcov", ".xml"}


def report_files(paths):
    files = []
    for path in map(Path, paths):
        files += sorted(f for f in path.iterdir() if f.suffix in REPORTS) if path.is_dir() else [path]
    return files


def lcov(report):
    source = None
    for line in report.read_text(encoding="utf-8").splitlines():
        if line.startswith("SF:"):
            source = line[3:]
        elif line.startswith("DA:"):
            number, hits = line[3:].split(",")[:2]
            yield (source, int(number)), int(hits) > 0


def cobertura(report):
    # The reports come from coverage.py and Pester earlier in the same CI job, not from anyone outside it.
    root = ET.parse(report).getroot()  # noqa: S314
    for cls in root.iter("class"):
        for line in cls.iter("line"):
            yield (cls.get("filename"), int(line.attrib["number"])), int(line.attrib["hits"]) > 0


def lines(paths):
    """(lines covered, lines found) over the reports, a line covered when any report hit it."""
    covered = {}
    for report in report_files(paths):
        for key, hit in (cobertura if report.suffix == ".xml" else lcov)(report):
            covered[key] = covered.get(key, False) or hit
    return sum(covered.values()), len(covered)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Fails when a language's line coverage is under the floor.")
    ap.add_argument("language")
    ap.add_argument("reports", nargs="+")
    ns = ap.parse_args(argv)
    missing = [p for p in ns.reports if not Path(p).exists()]
    if missing:
        print(f"{ns.language}: report not found: {', '.join(missing)}")
        return 2
    hit, found = lines(ns.reports)
    if not found:
        print(f"{ns.language}: no lines in {', '.join(ns.reports)}")
        return 2
    percent = 100.0 * hit / found
    under = percent < FLOOR
    print(f"{ns.language}: {percent:.1f}% of {found} lines covered" + (f", under the {FLOOR}% floor" if under else ""))
    return 1 if under else 0


if __name__ == "__main__":
    sys.exit(main())
