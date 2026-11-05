"""The Mac dialog, results window and question, driven through System Events outside Dorico. It needs a Mac desktop
session where osascript may control the computer (Accessibility), as GitHub's macOS runners allow, and skips
anywhere else.

    python tests/dialog/test_mac_dialog.py

With HBUC_JS_COVERAGE set to a folder, osascript runs a copy of mac.js that counts its statements, and each run
writes its counts into the folder (launch.py); node tests/dialog/mac_coverage.js merges them. With HBUC_SCREENSHOTS
set to a folder, a driver step that fails leaves a screenshot there.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(HERE))
import launch  # noqa: E402
import run_tests  # noqa: E402

DRIVE = HERE / "mac_drive.js"
TITLE = "Create a Handbells/Handchimes/SMBs Used Chart"
RESULTS = "Handbells Used Chart"
LUA = run_tests.find_lua()
INSTRUMENTED = None


def setUpModule():
    global INSTRUMENTED
    if sys.platform != "darwin":
        raise unittest.SkipTest("the Mac dialog runs only on macOS")
    if os.environ.get("HBUC_JS_COVERAGE"):
        INSTRUMENTED = Path(tempfile.mkdtemp()) / "mac.js"
        subprocess.run([shutil.which("node"), str(HERE / "instrument_mac.js"), str(launch.MAC_JS), str(INSTRUMENTED)],
                       check=True)


def start(*args):
    argv, env = launch.mac_command([str(a) for a in args], os.environ, INSTRUMENTED)
    return subprocess.Popen(argv, env=env)


def drive(proc, action, *args):
    """mac_drive.js's action on the window proc shows: what it printed, or None when it failed."""
    done = subprocess.run([*launch.OSASCRIPT, str(DRIVE), str(proc.pid), action, *map(str, args)],
                          capture_output=True, text=True, timeout=90)
    if done.returncode == 0:
        return done.stdout.strip()
    sys.stderr.write(f"\nmac_drive.js {action} {' '.join(map(str, args))}: {done.stderr.strip()}\n")
    shots = os.environ.get("HBUC_SCREENSHOTS")
    if shots:
        subprocess.run(["screencapture", "-x", str(Path(shots) / f"{action}-{uuid.uuid4().hex[:8]}.png")])
    return None


def dump(proc):
    return json.loads(drive(proc, "dump") or "null")


class DialogTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.request = self.tmp / "request.json"
        self.response = self.tmp / "response.json"

    def make(self, kind, settings=""):
        subprocess.run([LUA, str(HERE / "make_request.lua"), "request", kind, str(self.request), settings], check=True)

    def open(self, *args):
        proc = start(*args)
        self.addCleanup(lambda: proc.poll() is None and proc.kill())
        title = drive(proc, "wait")
        self.assertIsNotNone(title, "no window opened")
        return proc, title

    def open_dialog(self):
        proc, title = self.open(self.request, self.response)
        self.assertEqual(title, TITLE)
        return proc

    def press(self, proc, title):
        self.assertIsNotNone(drive(proc, "press", title), f"no {title} button")

    def response_json(self, proc):
        self.assertEqual(proc.wait(30), 0)
        raw = self.response.read_bytes()
        self.assertFalse(raw.startswith(b"\xef\xbb\xbf"), "no byte-order mark")
        return json.loads(raw.decode("utf-8"))

    def parsed(self):
        out = subprocess.run([LUA, str(HERE / "make_request.lua"), "parse", str(self.request), str(self.response)],
                             capture_output=True, text=True, check=True).stdout
        return json.loads(out)

    def request_json(self):
        return json.loads(self.request.read_text(encoding="utf-8"))

    def test_ok_returns_the_preselected_options(self):
        self.make("fixture", '{"excluded":"Organ"}')
        proc = self.open_dialog()
        self.press(proc, "OK")
        resp = self.response_json(proc)
        self.assertEqual(resp["version"], "1.0.0")
        self.assertFalse(resp["cancelled"])
        self.assertEqual(resp["mode"], "One combined chart")
        self.assertEqual(resp["heads"]["bells"], "noteheadset.default")
        self.assertEqual(resp["heads"]["chimes"], "noteheadset.diamondNoteheads")
        self.assertEqual(resp["colours"]["chimes"], "#c80000")
        self.assertEqual(resp["runId"], "t1")
        self.assertIn(resp["atPitch"], ([], {}))
        parsed = self.parsed()
        self.assertEqual(parsed["instruments"], ["Handbells (A)", "Handbells (B)"])
        self.assertEqual(parsed["mode"], "combined")
        self.assertEqual(parsed["heads"]["smbs"], "(no notehead)")
        self.assertEqual(parsed["remove"], False)
        self.assertIs(resp["newPage"], True, "the music starts a new page unless that was turned off")
        self.assertIs(parsed["newPage"], True)

    def test_remembered_no_new_page_comes_back(self):
        self.make("fixture", '{"newPage":false}')
        proc = self.open_dialog()
        self.press(proc, "OK")
        self.assertIs(self.response_json(proc)["newPage"], False)
        self.assertIs(self.parsed()["newPage"], False)

    def test_cancel_returns_cancelled(self):
        self.make("fixture")
        proc = self.open_dialog()
        self.press(proc, "Cancel")
        resp = self.response_json(proc)
        self.assertTrue(resp["cancelled"])
        self.assertEqual(resp["runId"], "t1")
        self.assertEqual(self.parsed(), {"parsed": False})

    def test_single_instrument_request_still_lists(self):
        self.make("single")
        proc = self.open_dialog()
        self.press(proc, "OK")
        self.assertIn(self.response_json(proc)["instruments"], (["Handbells"], "Handbells"))
        self.assertEqual(self.parsed()["instruments"], ["Handbells"])

    def test_remembered_at_pitch_comes_back(self):
        self.make("fixture", '{"atPitch":"Organ"}')
        proc = self.open_dialog()
        self.press(proc, "OK")
        self.assertIn(self.response_json(proc)["atPitch"], (["Organ"], "Organ"))
        self.assertEqual(self.parsed()["atPitch"], ["Organ"])

    def test_enter_presses_ok(self):
        self.make("fixture", '{"excluded":"Organ"}')
        proc = self.open_dialog()
        self.assertIsNotNone(drive(proc, "key", "return"))
        try:
            proc.wait(10)
        except subprocess.TimeoutExpired:
            drive(proc, "press", "Cancel")
            self.fail("Return did not close the dialog")
        self.assertFalse(self.response_json(proc)["cancelled"])
        self.assertEqual(self.parsed()["instruments"], ["Handbells (A)", "Handbells (B)"])

    def test_ticks_and_written_as_count_at_once(self):
        # the fixture's rows: Handbells (A) and (B) ticked, Organ not
        self.make("fixture", '{"excluded":"Organ"}')
        proc = self.open_dialog()
        charts = len(self.request_json()["instruments"])  # the pop-ups: each row's Written as, then Charts
        self.assertTrue(dump(proc)["popups"][charts]["enabled"], "two ticked: Charts is on")
        self.assertIsNotNone(drive(proc, "tick", 1))
        self.assertFalse(dump(proc)["popups"][charts]["enabled"], "one ticked: Charts is off")
        self.assertIsNotNone(drive(proc, "tick", 2))
        self.assertTrue(dump(proc)["popups"][charts]["enabled"], "two ticked again")
        self.assertIsNotNone(drive(proc, "pick", 2, 1), "Organ's Written as: at pitch")
        self.press(proc, "OK")
        self.response_json(proc)
        parsed = self.parsed()
        self.assertEqual(parsed["instruments"], ["Handbells (A)", "Organ"])
        self.assertEqual(parsed["atPitch"], ["Organ"])

    def test_picking_a_notehead_fills_its_colour(self):
        self.make("fixture")
        proc = self.open_dialog()
        req = self.request_json()
        kinds = [k["kind"] for k in req["kinds"]]
        coloured = [k["kind"] for k in req["kinds"] if k.get("colourLabel")]
        # after the Written as pop-ups and Charts, each kind has a notehead pop-up and a shape pop-up
        chimes_head = len(req["instruments"]) + 1 + 2 * kinds.index("chimes")
        rectangular = [h["id"] for h in req["noteheads"]].index("noteheadset.rectangular")
        self.assertIsNotNone(drive(proc, "pick", chimes_head, rectangular))
        self.assertEqual(dump(proc)["fields"][coloured.index("chimes")], "#008000",
                         "the colour most of the notehead's notes carry")
        self.press(proc, "OK")
        resp = self.response_json(proc)
        self.assertEqual(resp["heads"]["chimes"], "noteheadset.rectangular")
        self.assertEqual(resp["colours"]["chimes"], "#008000")

    def test_many_instruments_fit_and_return(self):
        self.make("many")
        proc = self.open_dialog()
        shown = dump(proc)
        (x, y), (w, h) = shown["position"], shown["size"]
        self.assertLessEqual(y + h, shown["screen"][1], "the window, with its OK button, is on the screen")
        self.assertLessEqual(x + w, shown["screen"][0])
        self.press(proc, "OK")
        self.response_json(proc)
        self.assertEqual(len(self.parsed()["instruments"]), 25)

    def test_names_differing_in_case_are_told_apart(self):
        self.make("cased", '{"excluded":"HANDBELLS","atPitch":"Handbells"}')
        proc = self.open_dialog()
        self.press(proc, "OK")
        self.response_json(proc)
        parsed = self.parsed()
        self.assertEqual(parsed["instruments"], ["Handbells"], "HANDBELLS stays unticked")
        self.assertEqual(parsed["atPitch"], ["Handbells"], "only Handbells is at pitch")

    def test_unreadable_request_answers_a_cancel_and_shows_it(self):
        missing = self.tmp / "missing.json"
        proc, _ = self.open(missing, self.response)
        texts = dump(proc)["texts"]
        self.assertTrue(any(f"cannot read {missing}" in (t or "") for t in texts), texts)
        self.press(proc, "OK")
        resp = self.response_json(proc)
        self.assertIs(resp["cancelled"], True)
        self.assertIn("cannot read", resp["error"])

    def show_message(self, **message):
        path = self.tmp / "message.json"
        path.write_text(json.dumps({"title": RESULTS, "kind": "info", **message}), encoding="utf-8")
        return self.open("--message", path)[0]

    def test_message_window_closes_on_ok(self):
        proc = self.show_message(text="Handbells Used: 2\nSMBs Used: 1")
        texts = dump(proc)["texts"]
        self.assertIn(RESULTS, texts)
        self.assertTrue(any("Handbells Used: 2" in (t or "") for t in texts), texts)
        self.press(proc, "OK")
        self.assertEqual(proc.wait(30), 0)

    def test_message_window_takes_its_ok_label(self):
        proc = self.show_message(text="Done", ok="Close")
        pressed = drive(proc, "press", "Close")
        if pressed is None:
            drive(proc, "press", "OK")
        self.assertIsNotNone(pressed, "the button carries the plug-in's label")
        self.assertEqual(proc.wait(30), 0)

    def test_escape_closes_the_message_window(self):
        proc = self.show_message(kind="warning", text="Some bells were skipped")
        self.assertIsNotNone(drive(proc, "key", "escape"))
        try:
            self.assertEqual(proc.wait(10), 0)
        except subprocess.TimeoutExpired:
            drive(proc, "press", "OK")
            self.fail("Escape did not close the results window")

    CHOICE = {"title": "Handbells Used Chart",
              "text": "The music uses more than one diamond notehead:\n\nDiamond Noteheads: 435 notes\n"
                      "Old-Style Diamond Noteheads: 1 note\n\nCombine them all as Diamond Noteheads, or keep them"
                      " separate?",
              "buttons": [{"id": "combine", "label": "Combine"}, {"id": "separate", "label": "Keep separate"}],
              "cancel": "separate"}

    def open_choice(self, spec):
        path = self.tmp / "choice.json"
        path.write_text(spec, encoding="utf-8")
        return self.open("--choice", path, self.response)[0]

    def test_choice_returns_the_pressed_button(self):
        proc = self.open_choice(json.dumps(self.CHOICE))
        self.press(proc, "Combine")
        self.assertEqual(self.response_json(proc), {"choice": "combine"})

    def test_choice_escape_is_its_cancel(self):
        proc = self.open_choice(json.dumps(self.CHOICE))
        self.assertIsNotNone(drive(proc, "key", "escape"))
        self.assertEqual(self.response_json(proc), {"choice": "separate"})

    def test_choice_answers_when_it_fails(self):
        # a file that isn't JSON stops the script before any window opens: it still answers, with the reason
        path = self.tmp / "choice.json"
        path.write_text("not json", encoding="utf-8")
        got = self.response_json(start("--choice", path, self.response))
        self.assertTrue(got.pop("error", ""))
        self.assertEqual(got, {"choice": ""}, "the file named no cancel button (hbuc/dorico/dialog.lua reads any "
                                              "answer with an error as no choice)")


if __name__ == "__main__":
    unittest.main()
