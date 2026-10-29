"""The Windows dialog and results window, driven through UI Automation outside Dorico (needs a desktop session).

    python tests/dialog/test_windows_dialog.py
"""
import json
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tools"))
import run_tests  # noqa: E402

PS1 = ROOT / "plugin" / "Handbells Used Chart" / "dialog" / "windows.ps1"
CLICK = ROOT / "tools" / "dorico" / "click.ps1"
GRID_CLICK = ROOT / "tools" / "dorico" / "gridclick.ps1"
PRESS_KEY = ROOT / "tools" / "dorico" / "presskey.ps1"
HAS_WINDOW = ROOT / "tools" / "dorico" / "haswindow.ps1"
CAPTURE = ROOT / "tools" / "dorico" / "capture.ps1"
FITS = HERE / "fits.ps1"
TITLE = "Create a Handbells/Handchimes/SMBs Used Chart"
RESULTS = "Handbells Used Chart"
LUA = run_tests.find_lua()


def powershell(*args, **kw):
    return subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", *args],
                          capture_output=True, text=True, **kw)


def window_exists(title):
    # Win32's window list, not UI Automation's (haswindow.ps1 says why); a lookup that still hangs counts as "no"
    try:
        return powershell("-File", str(HAS_WINDOW), "-Title", title, timeout=30).stdout.strip() == "yes"
    except subprocess.TimeoutExpired:
        return False


def wait_window(title, timeout=60):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if window_exists(title):
            return True
        time.sleep(0.5)
    return False


def click(title, button):
    return powershell("-File", str(CLICK), "-Window", title, "-Button", button).returncode == 0


def click_cell(row, column, shown, keys=()):
    args = ["-File", str(GRID_CLICK), "-Window", TITLE, "-Row", str(row), "-Column", str(column), "-Shown", str(shown)]
    if keys:
        args += ["-Keys", ",".join(keys)]
    return powershell(*args).returncode == 0


def enabled(title, name):
    script = ("Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes; "
              "$a=[System.Windows.Automation.AutomationElement]; $s=[System.Windows.Automation.TreeScope]; "
              "$w=$a::RootElement.FindFirst($s::Children, (New-Object System.Windows.Automation.PropertyCondition("
              "$a::NameProperty, '" + title + "'))); "
              "$e=$w.FindFirst($s::Descendants, (New-Object System.Windows.Automation.PropertyCondition("
              "$a::NameProperty, '" + name + "'))); $e.Current.IsEnabled")
    return powershell("-Command", script).stdout.strip() == "True"


class DialogTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.request = self.tmp / "request.json"
        self.response = self.tmp / "response.json"

    def make(self, kind, settings=""):
        subprocess.run([LUA, str(HERE / "make_request.lua"), "request", kind, str(self.request), settings], check=True)

    def open_dialog(self):
        proc = subprocess.Popen(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
                                 "-File", str(PS1), "-Request", str(self.request), "-Response", str(self.response)])
        self.addCleanup(lambda: proc.poll() is None and proc.kill())
        self.assertTrue(wait_window(TITLE), "the dialog did not open")
        return proc

    def response_json(self, proc):
        self.assertEqual(proc.wait(30), 0)
        raw = self.response.read_bytes()
        self.assertFalse(raw.startswith(b"\xef\xbb\xbf"), "no byte-order mark")
        return json.loads(raw.decode("utf-8"))

    def parsed(self):
        out = subprocess.run([LUA, str(HERE / "make_request.lua"), "parse", str(self.request), str(self.response)],
                             capture_output=True, text=True, check=True).stdout
        return json.loads(out)

    def test_ok_returns_the_preselected_options(self):
        self.make("fixture", '{"excluded":"Organ"}')
        proc = self.open_dialog()
        time.sleep(1)
        powershell("-File", str(CAPTURE), "-ProcessId", str(proc.pid), "-Out",
                   str(ROOT / "images" / "dialog.png"), "-TitleLike", TITLE)
        self.assertTrue(click(TITLE, "OK"))
        resp = self.response_json(proc)
        self.assertEqual(resp["version"], "0.1.0")
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
        self.assertTrue(click(TITLE, "OK"))
        self.assertIs(self.response_json(proc)["newPage"], False)
        self.assertIs(self.parsed()["newPage"], False)

    def test_cancel_returns_cancelled(self):
        self.make("fixture")
        proc = self.open_dialog()
        self.assertTrue(click(TITLE, "Cancel"))
        resp = self.response_json(proc)
        self.assertTrue(resp["cancelled"])
        self.assertEqual(resp["runId"], "t1")
        self.assertEqual(self.parsed(), {"parsed": False})

    def test_single_instrument_request_still_lists(self):
        self.make("single")
        proc = self.open_dialog()
        self.assertTrue(click(TITLE, "OK"))
        resp = self.response_json(proc)
        self.assertIn(resp["instruments"], (["Handbells"], "Handbells"))
        self.assertEqual(self.parsed()["instruments"], ["Handbells"])

    def test_remembered_at_pitch_comes_back(self):
        self.make("fixture", '{"atPitch":"Organ"}')
        proc = self.open_dialog()
        self.assertTrue(click(TITLE, "OK"))
        resp = self.response_json(proc)
        self.assertIn(resp["atPitch"], (["Organ"], "Organ"))
        self.assertEqual(self.parsed()["atPitch"], ["Organ"])

    def test_enter_presses_ok(self):
        # the table must not take the first focus: it keeps Enter for moving down a row
        self.make("fixture", '{"excluded":"Organ"}')
        proc = self.open_dialog()
        time.sleep(1)
        self.assertEqual(powershell("-File", str(PRESS_KEY), "-Window", TITLE, "-Key", "Return").returncode, 0)
        try:
            proc.wait(10)
        except subprocess.TimeoutExpired:
            click(TITLE, "Cancel")
            self.fail("Enter did not close the dialog")
        self.assertFalse(self.response_json(proc)["cancelled"])
        self.assertEqual(self.parsed()["instruments"], ["Handbells (A)", "Handbells (B)"])

    def test_ticks_and_written_as_count_at_once(self):
        # the fixture's rows: Handbells (A) and (B) ticked, Organ not
        self.make("fixture", '{"excluded":"Organ"}')
        proc = self.open_dialog()
        time.sleep(1)
        self.assertTrue(enabled(TITLE, "One combined chart"), "two ticked: Charts is on")
        self.assertTrue(click_cell(1, 0, 3))
        self.assertFalse(enabled(TITLE, "One combined chart"), "one ticked: Charts is off")
        self.assertTrue(click_cell(2, 0, 3))
        self.assertTrue(enabled(TITLE, "One combined chart"), "two ticked again")
        self.assertTrue(click_cell(2, 2, 3, ["Down", "Return"]))
        self.assertTrue(click(TITLE, "OK"))
        self.response_json(proc)
        parsed = self.parsed()
        self.assertEqual(parsed["instruments"], ["Handbells (A)", "Organ"])
        self.assertEqual(parsed["atPitch"], ["Organ"])

    def test_many_instruments_fit_and_return(self):
        self.make("many")
        proc = self.open_dialog()
        time.sleep(1)
        powershell("-File", str(CAPTURE), "-ProcessId", str(proc.pid), "-Out",
                   str(Path(tempfile.gettempdir()) / "hbuc-dialog-many.png"), "-TitleLike", TITLE)
        self.assertTrue(click(TITLE, "OK"))
        self.response_json(proc)
        self.assertEqual(len(self.parsed()["instruments"]), 25)

    def test_message_window_takes_its_ok_label(self):
        message = self.tmp / "message.json"
        message.write_text(json.dumps({"title": RESULTS, "kind": "info", "text": "Done", "ok": "Close"}),
                           encoding="utf-8")
        proc = subprocess.Popen(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
                                 "-File", str(PS1), "-Message", str(message)])
        self.addCleanup(lambda: proc.poll() is None and proc.kill())
        self.assertTrue(wait_window(RESULTS))
        pressed = click(RESULTS, "Close")
        if not pressed:
            click(RESULTS, "OK")
        self.assertTrue(pressed, "the button carries the plug-in's label")
        self.assertEqual(proc.wait(30), 0)

    def test_names_differing_in_case_are_told_apart(self):
        self.make("cased", '{"excluded":"HANDBELLS","atPitch":"Handbells"}')
        proc = self.open_dialog()
        self.assertTrue(click(TITLE, "OK"))
        self.response_json(proc)
        parsed = self.parsed()
        self.assertEqual(parsed["instruments"], ["Handbells"], "HANDBELLS stays unticked")
        self.assertEqual(parsed["atPitch"], ["Handbells"], "only Handbells is at pitch")

    def show_message(self, text):
        message = self.tmp / "message.json"
        message.write_text(json.dumps({"title": RESULTS, "kind": "warning", "text": text}), encoding="utf-8")
        proc = subprocess.Popen(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
                                 "-File", str(PS1), "-Message", str(message)])
        self.addCleanup(lambda: proc.poll() is None and proc.kill())
        self.assertTrue(wait_window(RESULTS))
        return proc

    def test_long_message_fits_the_screen(self):
        proc = self.show_message("\n".join(f"Line {i}: bells outside C2-C9 were skipped" for i in range(200)))
        time.sleep(1)
        fits = powershell("-File", str(FITS), "-Title", RESULTS, "-Button", "OK").stdout.strip()
        self.assertTrue(click(RESULTS, "OK"))
        self.assertEqual(proc.wait(30), 0)
        self.assertEqual(fits, "yes", "the window and its OK button are on the screen")

    def open_mode(self, flag, payload, title):
        path = self.tmp / f"{flag.lower()}.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        proc = subprocess.Popen(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
                                 "-File", str(PS1), f"-{flag}", str(path), "-Response", str(self.response)])
        self.addCleanup(lambda: proc.poll() is None and proc.kill())
        self.assertTrue(wait_window(title), f"{title} did not open")
        time.sleep(1)
        return proc

    CHOICE = {"title": "Noteheads changed in Dorico", "text": "Export the score as MusicXML.",
              "buttons": [{"id": "export", "label": "Export MusicXML"}, {"id": "choose", "label": "Choose file"},
                          {"id": "cancel", "label": "Cancel"}], "cancel": "cancel"}

    def test_choice_returns_the_pressed_button(self):
        proc = self.open_mode("Choice", self.CHOICE, self.CHOICE["title"])
        self.assertTrue(click(self.CHOICE["title"], "Choose file"))
        self.assertEqual(self.response_json(proc), {"choice": "choose"})

    def test_choice_escape_is_its_cancel(self):
        proc = self.open_mode("Choice", self.CHOICE, self.CHOICE["title"])
        self.assertEqual(powershell("-File", str(PRESS_KEY), "-Window", self.CHOICE["title"], "-Key", "Escape")
                         .returncode, 0)
        self.assertEqual(self.response_json(proc), {"choice": "cancel"})

    def pick(self, button, names=("a - Full score - 01 Flow.musicxml",)):
        folder = self.tmp / "Flows from Bells & Chimes"
        folder.mkdir()
        for name in names:
            (folder / name).write_text("<score-partwise/>", encoding="utf-8")
        title = "Choose the MusicXML export"
        proc = self.open_mode("Pick", {"title": title, "folder": str(folder).replace("\\", "/"), "files": list(names),
                                       "filter": {"name": "MusicXML", "extensions": ["musicxml", "xml"]}}, title)
        # UI Automation lists the picker under its owner, so presskey can't find it: click.ps1 finds it through Win32
        self.assertTrue(click(title, button))
        return folder, self.response_json(proc)

    def test_pick_returns_the_preselected_file(self):
        folder, answer = self.pick("Open")
        self.assertEqual([Path(p) for p in answer["files"]], [folder / "a - Full score - 01 Flow.musicxml"])

    def test_pick_returns_every_preselected_file(self):
        names = ("a - Full score - 01 Flow.musicxml", "a - Full score - 02 Other.musicxml")
        folder, answer = self.pick("Open", names)
        self.assertEqual(sorted(Path(p) for p in answer["files"]), sorted(folder / n for n in names))

    def test_pick_takes_and_returns_code_page_paths(self):
        # Dorico's Lua names files in the ANSI code page ("mbcs" here) and opens them only by those bytes
        folder = self.tmp / "Flows from Noël"
        folder.mkdir()
        name = "Noël - Full score - 01 Noël.musicxml"
        (folder / name).write_text("<score-partwise/>", encoding="utf-8")
        title = "Choose the MusicXML export"
        lua_folder = str(folder).replace("\\", "/") + "/"
        proc = self.open_mode("Pick", {"title": title, "folder": "", "folderBytes": lua_folder.encode("mbcs").hex(),
                                       "files": [], "filesBytes": [name.encode("mbcs").hex()],
                                       "filter": {"name": "MusicXML", "extensions": ["musicxml"]}}, title)
        self.assertTrue(click(title, "Open"))
        answer = self.response_json(proc)
        self.assertEqual([Path(p) for p in answer["files"]], [folder / name])
        self.assertEqual([bytes.fromhex(h) for h in answer["filesBytes"]], [str(folder / name).encode("mbcs")])

    def test_pick_takes_utf8_paths_too(self):
        # the project's folder comes from Dorico's text export in UTF-8, unlike the names lfs lists
        folder = self.tmp / "Flows from Noël"
        folder.mkdir()
        name = "Noël - Full score - 01 Noël.musicxml"
        (folder / name).write_text("<score-partwise/>", encoding="utf-8")
        title = "Choose the MusicXML export"
        lua_folder = str(folder).replace("\\", "/") + "/"
        proc = self.open_mode("Pick", {"title": title, "folder": "", "folderBytes": lua_folder.encode("utf-8").hex(),
                                       "files": [], "filesBytes": [name.encode("utf-8").hex()],
                                       "filter": {"name": "MusicXML", "extensions": ["musicxml"]}}, title)
        self.assertTrue(click(title, "Open"))
        self.assertEqual([Path(p) for p in self.response_json(proc)["files"]], [folder / name])

    def test_choice_and_pick_answer_when_they_fail(self):
        # a file that isn't JSON stops the script before any window opens: it still answers, with the reason
        for flag, answer in (("Choice", {"choice": None}), ("Pick", {"files": [], "filesBytes": []})):
            spec = self.tmp / f"{flag.lower()}.json"
            spec.write_text("not json", encoding="utf-8")
            self.response.unlink(missing_ok=True)
            proc = subprocess.Popen(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
                                     "-File", str(PS1), f"-{flag}", str(spec), "-Response", str(self.response)])
            got = self.response_json(proc)
            self.assertTrue(got.pop("error", ""), flag)
            self.assertEqual(got, answer, flag)

    def test_pick_cancel_returns_no_files(self):
        _, answer = self.pick("Cancel")
        self.assertEqual(answer, {"files": [], "filesBytes": []})

    def test_message_window_closes_on_ok(self):
        message = self.tmp / "message.json"
        message.write_text(json.dumps({"title": RESULTS, "kind": "info", "text": "Handbells Used: 2\nSMBs Used: 1"}),
                           encoding="utf-8")
        proc = subprocess.Popen(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
                                 "-File", str(PS1), "-Message", str(message)])
        self.addCleanup(lambda: proc.poll() is None and proc.kill())
        self.assertTrue(wait_window(RESULTS))
        self.assertTrue(click(RESULTS, "OK"))
        self.assertEqual(proc.wait(30), 0)


if __name__ == "__main__":
    unittest.main()
