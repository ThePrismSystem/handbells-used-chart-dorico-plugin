"""The Mac dialog script, checked without a Mac.

    python tests/dialog/test_mac_script.py

AppKit can't run here. Its syntax is checked with Node (or esprima, when Node is missing). Its pure parts, which
read the request, set the starting choices and build the response, run under Node through mac_harness.js, and
the answer goes back through the plug-in's own parser. Tests that need Node skip without it.
"""
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tools"))
import run_tests  # noqa: E402

MAC_JS = ROOT / "plugin" / "Handbells Used Chart" / "dialog" / "mac.js"
HARNESS = HERE / "mac_harness.js"
NODE = shutil.which("node")
LUA = run_tests.find_lua()


class MacScriptTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def need_node(self):
        if not NODE:
            self.skipTest("Node is not installed")

    def evaluate(self, expression):
        self.need_node()
        out = subprocess.run([NODE, str(HARNESS), str(MAC_JS), "eval", expression], capture_output=True, text=True,
                             check=True).stdout
        return json.loads(out)

    def answer(self, kind, settings=""):
        """The Mac script's answer to OK pressed at once, as the plug-in parses it."""
        self.need_node()
        if not LUA:
            self.skipTest("Lua 5.2 is not installed")
        request, response = self.tmp / "request.json", self.tmp / "response.json"
        subprocess.run([LUA, str(HERE / "make_request.lua"), "request", kind, str(request), settings], check=True)
        subprocess.run([NODE, str(HARNESS), str(MAC_JS), "respond", str(request), str(response)], check=True)
        raw = json.loads(response.read_text(encoding="utf-8"))
        out = subprocess.run([LUA, str(HERE / "make_request.lua"), "parse", str(request), str(response)],
                             capture_output=True, text=True, check=True).stdout
        return raw, json.loads(out)

    def test_mac_script_parses(self):
        if NODE:
            proc = subprocess.run([NODE, "--check", str(MAC_JS)], capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            return
        try:
            import esprima
        except ImportError:
            self.skipTest("neither Node nor esprima is installed")
        esprima.parseScript(MAC_JS.read_text(encoding="utf-8"))

    def test_mac_script_writes_every_response_field(self):
        source = MAC_JS.read_text(encoding="utf-8")
        for field in ("version", "runId", "cancelled", "instruments", "atPitch", "mode", "heads", "shapes", "colours",
                      "remove", "newPage"):
            self.assertIn(field, source)

    def test_mac_windows_stay_usable_without_activation(self):
        # AppKit can't run here, so these pin the defences in the source
        source = MAC_JS.read_text(encoding="utf-8")
        alert = source[source.index("function showAlert"):source.index("function run(")]
        self.assertIn("setHidesOnDeactivate(false)", alert,
                      "an alert hidden when activation is refused would leave Dorico waiting on nothing")
        self.assertIn("setLevel(3)", alert, "above Dorico's windows, like the settings window")
        popup = source[source.index("function addPopup"):source.index("function addCheckbox")]
        self.assertIn("setAutoenablesItems(false)", popup, "items added by hand have no action, so would be greyed")
        self.assertIn("ui.target = target", source, "a control holds its target weakly")

    def test_text_fields_take_the_edit_keys(self):
        # Cmd-X, C, V, A and Z reach a text field through the main menu, and an app osascript starts has none
        source = MAC_JS.read_text(encoding="utf-8")
        menu = source[source.index("function installEditMenu"):source.index("function run(")]
        for selector, key in (("cut:", "x"), ("copy:", "c"), ("paste:", "v"), ("selectAll:", "a"), ("undo:", "z")):
            self.assertIn(f'"{selector}", "{key}"', menu)
        self.assertIn("setMainMenu", menu)
        self.assertIn("installEditMenu(app)", source[source.index("function run("):])

    def test_written_as_fits_its_longest_choice(self):
        self.assertEqual(self.evaluate("settingsWidth(200)"), 660, "the usual width when the choices fit")
        self.assertEqual(self.evaluate("settingsWidth(290)"), 660)
        self.assertEqual(self.evaluate("settingsWidth(400)"), 770, "wider for a longer choice")
        self.assertEqual(self.evaluate("settingsWidth(400.2)"), 771)
        source = MAC_JS.read_text(encoding="utf-8")
        self.assertIn("settingsWidth(fittedWidth(", source, "measured by AppKit in the real dialog")

    def test_results_alert_takes_its_label_and_escape(self):
        source = MAC_JS.read_text(encoding="utf-8")
        alert = source[source.index("function showAlert"):source.index("function installEditMenu")]
        self.assertNotIn('addButtonWithTitle("OK")', alert, "the label comes from the plug-in")
        self.assertIn('"\\u001b"', alert, "Escape closes it, as on Windows")
        self.assertIn("performClick:", alert)
        self.assertIn('field(message, "ok")', source)

    def test_answer_skips_without_lua(self):
        saved = globals()["LUA"]
        globals()["LUA"] = None
        try:
            with self.assertRaises(unittest.SkipTest):
                self.answer("single")
        finally:
            globals()["LUA"] = saved

    def test_ok_at_once_returns_the_preselected_options(self):
        raw, parsed = self.answer("fixture", '{"excluded":"Organ","atPitch":"Organ"}')
        self.assertEqual(raw["runId"], "t1")
        self.assertIs(raw["cancelled"], False)
        self.assertEqual(raw["version"], "0.1.0")
        self.assertEqual(raw["colours"]["chimes"], "#c80000")
        self.assertEqual(parsed["instruments"], ["Handbells (A)", "Handbells (B)"])
        self.assertEqual(parsed["atPitch"], ["Organ"])
        self.assertEqual(parsed["mode"], "combined")
        self.assertEqual(parsed["heads"]["bells"], "noteheadset.default")
        self.assertEqual(parsed["heads"]["chimes"], "noteheadset.diamondNoteheads")
        self.assertEqual(parsed["heads"]["smbs"], "(no notehead)")
        self.assertEqual(parsed["remove"], False)
        self.assertIs(raw["newPage"], True, "the music starts a new page unless that was turned off")
        self.assertIs(parsed["newPage"], True)

    def test_remembered_no_new_page_comes_back(self):
        raw, parsed = self.answer("fixture", '{"newPage":false}')
        self.assertIs(raw["newPage"], False)
        self.assertIs(parsed["newPage"], False)

    def test_one_instrument_and_many(self):
        self.assertEqual(self.answer("single")[1]["instruments"], ["Handbells"])
        self.assertEqual(len(self.answer("many")[1]["instruments"]), 25)

    def test_lua_empty_lists_read_as_empty(self):
        # Lua writes an empty list as {}; a one-item list may come as a bare string
        self.assertEqual(self.evaluate("toList({})"), [])
        self.assertEqual(self.evaluate("toList(undefined)"), [])
        self.assertEqual(self.evaluate("toList('Organ')"), ["Organ"])
        self.assertEqual(self.evaluate("toList(['a', 'b'])"), ["a", "b"])

    def test_picking_a_notehead_gives_its_majority_colour(self):
        model = "requestModel({noteheads: [{id: 'a', name: 'A'}, {id: 'b', name: 'B'}], colours: {b: '#c80000'}})"
        self.assertEqual(self.evaluate(f"colourFor({model}, 1)"), "#c80000")
        self.assertEqual(self.evaluate(f"colourFor({model}, 0)"), "")

    def test_charts_is_on_with_two_ticks(self):
        self.assertIs(self.evaluate("chartsEnabled([true, false, true])"), True)
        self.assertIs(self.evaluate("chartsEnabled([true, false, false])"), False)


if __name__ == "__main__":
    unittest.main()
