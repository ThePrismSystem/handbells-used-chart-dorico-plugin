"""Which edits does Edit.Undo take back when it is sent from inside a script?

    python spike/29_undo_experiments.py

Each experiment runs on its own fixture scratch copy. ("R", cmd) is sent through the Remote API between script
runs; ("S", [...]) runs spike/29_undo_inside.lua with those steps. The findings are in
docs/dorico-lua-guide.md, section 7.
"""
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tests" / "dorico"))
import harness  # noqa: E402

PROBE = REPO / "spike" / "29_undo_inside.lua"
RENAME_A = "Project.Flow.Rename?FlowID=0&Name=A"
RENAME_B = "Project.Flow.Rename?FlowID=0&Name=B"

EXPERIMENTS = {
    # E1-E3 and E5 send the "user's edit" through the Remote API, which refuses it (kError): kept for the record
    "E1 remote edit, then script new flow + undo": [("R", RENAME_A), ("S", ["NEWFLOW", "Edit.Undo"])],
    "E2 remote edit, then script undo only": [("R", RENAME_A), ("S", ["Edit.Undo"])],
    "E3 remote edit, empty script, then script new flow + undo": [("R", RENAME_A), ("S", []),
                                                                  ("S", ["NEWFLOW", "Edit.Undo"])],
    "E4 script: edit, new flow, undo": [("S", [RENAME_B, "NEWFLOW", "Edit.Undo"])],
    "E5 remote edit, script new flow, then remote undo": [("R", RENAME_A), ("S", ["NEWFLOW"]), ("R", "Edit.Undo"),
                                                          ("S", [])],
    "E6 edit in an earlier script, then script new flow + undo": [("S", [RENAME_A]), ("S", ["NEWFLOW", "Edit.Undo"])],
    "E7 edit in an earlier script, then script undo only": [("S", [RENAME_A]), ("S", ["Edit.Undo"])],
    "E8 edit in an earlier script, script new flow + undo, then remote undo": [
        ("S", [RENAME_A]), ("S", ["NEWFLOW", "Edit.Undo"]), ("R", "Edit.Undo"), ("S", [])],
    "E9 edit in an earlier script, then one script: new flow + undo, twice": [
        ("S", [RENAME_A]), ("S", ["NEWFLOW", "Edit.Undo", "NEWFLOW", "Edit.Undo"])],
    "E10 edit in an earlier script, then one script: two new flows, one undo": [
        ("S", [RENAME_A]), ("S", ["NEWFLOW", "NEWFLOW", "Edit.Undo"]), ("R", "Edit.Undo"), ("S", [])],
}


def run_script(client, steps):
    code, result, _ = harness.run_lua.run(PROBE, on_active=True, client=client, timeout=120, extra_args={
        "steps": steps, "expectScratch": {"path": harness.run_lua.fwd(harness.SCRATCH)}})
    f = (result or {}).get("facts", {})
    return f"before[{f.get('before')}] steps{f.get('steps')} after[{f.get('after')}]"


class T:  # harness.scratch wants a TestCase-like object
    def assertIsNotNone(self, v, msg=None):
        if v is None:
            raise AssertionError(msg)

    def assertTrue(self, v, msg=None):
        if not v:
            raise AssertionError(msg)


if __name__ == "__main__":
    only = sys.argv[1:]
    for name, steps in EXPERIMENTS.items():
        if only and name.split()[0] not in only:
            continue
        print("==", name)
        with harness.scratch(T(), str(PROBE.relative_to(harness.HERE, walk_up=True)), args={"steps": []}) as (client, first):
            print("   opened:", first["facts"].get("after"))
            for kind, what in steps:
                if kind == "R":
                    print("   remote", what, client.command(what).get("code"))
                else:
                    print("   script", run_script(client, what))
