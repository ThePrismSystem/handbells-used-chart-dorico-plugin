"""Every process the shipped plug-in starts and every file call it makes, and that it makes no network calls.

    python -m unittest tests/test_shipped_calls.py
"""
import re
import sys
import unittest
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import package  # noqa: E402

# The commands the plug-in runs, as its code spells them. SECURITY.md describes each one.
PROCESSES = [
    "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File",
    "/usr/bin/osascript -l JavaScript",
    "/bin/mkdir -p",
    "/bin/sleep 1",
]

# What each shipped file may call, by zip path, and why. Anything not listed here must not appear.
ALLOWED = {
    "Handbells Used Chart/hbuc/main.lua": {
        "command File.Save": 1,  # saves the open project after OK, before anything changes
    },
    "Handbells Used Chart/hbuc/dorico/context.lua": {
        "os.getenv": 2,  # APPDATA, HOME, TEMP, TMP and TMPDIR: where the data and temp folders go
        "require lfs": 1,  # only to log whether Dorico has lfs
    },
    "Handbells Used Chart/hbuc/dorico/dialog.lua": {
        "os.execute": 2,  # starts the dialog script (PowerShell or osascript), and /bin/sleep 1 while a Mac waits
        "os.remove": 3,  # the last run's osascript.log and response file, for the dialog and for the message or picker
    },
    "Handbells Used Chart/hbuc/dorico/doc.lua": {
        "os.remove": 1,  # the last text export, before File.Export.Text writes a new one
        "command File.Export.Text": 1,  # Dorico writes the project's text export into the temp folder
    },
    "Handbells Used Chart/hbuc/dorico/musicxmlstep.lua": {
        "command File.Export": 1,  # opens Dorico's MusicXML export, which writes where its dialog says
    },
    "Handbells Used Chart/hbuc/dorico/files.lua": {
        "io.open": 2,  # reads and writes the plug-in's own files
        "os.execute": 1,  # /bin/mkdir -p for the plug-in's folders on a Mac
        "require lfs": 1,  # LuaFileSystem, which ships with Dorico on Windows
        "lfs.attributes": 5,  # whether a folder exists, when the project file and a MusicXML export last changed
        "lfs.dir": 2,  # the project folder's "Flows from" folders, to find the MusicXML export Dorico just wrote
        "lfs.mkdir": 1,  # the plug-in's folders on Windows
    },
    "Handbells Used Chart/hbuc/dorico/safe.lua": {
        "io.open": 2,  # the run log: emptied at the start, then added to line by line
    },
    "Handbells Used Chart/dialog/windows.ps1": {
        "Add-Type": 2,  # loads System.Windows.Forms and System.Drawing, and declares SetProcessDPIAware
        "DllImport": 1,  # SetProcessDPIAware from user32.dll, so the dialog is sharp on scaled displays
        "IO.File.ReadAllText": 1,  # the request file
        "IO.File.WriteAllText": 1,  # the response file
        "OpenFileDialog": 1,  # the picker for a MusicXML export, which returns the chosen paths and opens nothing
    },
    "Handbells Used Chart/dialog/mac.js": {
        "ObjC.import Cocoa": 1,  # AppKit, for the dialog's window
        "stringWithContentsOfFile": 1,  # the request file
        "writeToFile": 1,  # the response file
        "currentApplication": 1,  # osascript's own Standard Additions, for the file picker
        "chooseFile": 1,  # the picker for a MusicXML export, which returns the chosen paths and opens nothing
    },
}

LUA_CALLS = [
    ("os.execute", r"\bos\.execute\b"), ("io.popen", r"\bio\.popen\b"), ("io.open", r"\bio\.open\b"),
    ("io.lines", r"\bio\.lines\b"), ("os.remove", r"\bos\.remove\b"), ("os.rename", r"\bos\.rename\b"),
    ("os.tmpname", r"\bos\.tmpname\b"), ("os.getenv", r"\bos\.getenv\b"), ("load", r"(?<![\w.:])load\s*\("),
    ("io.output", r"\bio\.output\b"), ("io.input", r"\bio\.input\b"), ("io.tmpfile", r"\bio\.tmpfile\b"),
    ("loadstring", r"\bloadstring\b"), ("loadfile", r"\bloadfile\b"), ("dofile", r"\bdofile\b"),
    ("package.loadlib", r"\bpackage\.loadlib\b"),
]
PS1_CALLS = [
    ("Invoke-Expression", r"(?i)\bInvoke-Expression\b|(?<![\w$-])iex\b"),
    ("Start-Process", r"(?i)\bStart-Process\b|(?<![\w$-])saps\b"),
    ("start", r"(?i)(?<![\w$.:-])start\b(?![-\w])"), ("Diagnostics.Process", r"(?i)\b(?:System\.)?Diagnostics\.Process\b"),
    ("Invoke-Item", r"(?i)\bInvoke-Item\b|(?<![\w$.:-])ii\b"), ("Start-Job", r"(?i)\bStart-Job\b|(?<![\w$.:-])sajb\b"),
    ("Invoke-Command", r"(?i)\bInvoke-Command\b|(?<![\w$.:-])icm\b"),
    ("Set-ExecutionPolicy", r"(?i)\bSet-ExecutionPolicy\b"), ("Add-Type", r"(?i)\bAdd-Type\b"),
    ("DllImport", r"\bDllImport\b"), ("registry", r"(?i)\b(?:HKLM|HKCU|HKCR|HKU|HKCC|HKEY_[A-Z_]+)\b"),
    ("Remove-Item", r"(?i)\bRemove-Item\b"), ("Set-Content", r"(?i)\bSet-Content\b"),
    ("Add-Content", r"(?i)\bAdd-Content\b"), ("Out-File", r"(?i)\bOut-File\b"), ("New-Item", r"(?i)\bNew-Item\b"),
    ("Copy-Item", r"(?i)\bCopy-Item\b"), ("Move-Item", r"(?i)\bMove-Item\b"),
    ("OpenFileDialog", r"\bOpenFileDialog\b"),
]
JS_CALLS = [
    ("doShellScript", r"\bdoShellScript\b"), ("NSTask", r"\bNSTask\b"), ("Application()", r"\bApplication\s*\("),
    ("writeToFile", r"\bwriteToFile\w*"), ("stringWithContentsOfFile", r"\bstringWithContentsOfFile\w*"),
    ("NSFileManager", r"\bNSFileManager\b"), ("NSWorkspace", r"\bNSWorkspace\b"),
    ("NSAppleScript", r"\bNSAppleScript\b"), ("chooseFile", r"\bchooseFile\b"),
    ("currentApplication", r"\bcurrentApplication\b"),
]
NETWORK_CALLS = [
    ("Invoke-WebRequest", r"(?i)\bInvoke-WebRequest\b|(?<![\w$-])iwr\b"),
    ("Invoke-RestMethod", r"(?i)\bInvoke-RestMethod\b|(?<![\w$-])irm\b"),
    ("System.Net", r"(?i)\b(?:System\.)?Net\.[A-Za-z]\w*"), ("Start-BitsTransfer", r"(?i)\bStart-BitsTransfer\b"),
    ("NSURL", r"\bNSURL\w*"), ("NSURLSession", r"\bNSURLSession\b"),
    ("NSURLConnection", r"\bNSURLConnection\b"), ("ContentsOfURL", r"\w*ContentsOfURL\w*"),
    ("URL", r"(?i)\b(?:https?|ftp)://"), ("socket", r"(?i)\bsocket\b"), ("curl/wget", r"(?i)\b(?:curl|wget)\b"),
]
NETWORK = [name for name, _ in NETWORK_CALLS]

LUA_LONG = re.compile(r"\[(=*)\[")


def blank(text):
    """A removed comment: a space, so the tokens either side stay apart, and its newlines, so lines keep their numbers."""
    return " " + "\n" * text.count("\n")


def string_end(src, i, escape, multiline):
    """Where the string that opens at src[i] ends. An unterminated one ends at the line's end (or the file's)."""
    quote, j = src[i], i + 1
    while j < len(src):
        ch = src[j]
        if ch == escape:
            j += 2
            continue
        if ch == quote:
            if escape is None and src[j + 1:j + 2] == quote:  # PowerShell's '' inside '...'
                j += 2
                continue
            return j + 1
        if ch == "\n" and not multiline:
            return j
        j += 1
    return len(src)


def strip_lua_comments(src, keep_strings=True):
    """The code without its comments. keep_strings=False also empties every string, keeping its newlines."""
    def string(text):
        return text if keep_strings else '""' + "\n" * text.count("\n")
    out, i = [], 0
    while i < len(src):
        long = LUA_LONG.match(src, i + 2) if src.startswith("--", i) else None
        if src.startswith("--", i):
            if long:
                close = src.find("]" + long.group(1) + "]", long.end())
                end = len(src) if close < 0 else close + len(long.group(1)) + 2
            else:
                end = src.find("\n", i)
                end = len(src) if end < 0 else end
            out.append(blank(src[i:end]))
        elif LUA_LONG.match(src, i):
            opener = LUA_LONG.match(src, i)
            close = src.find("]" + opener.group(1) + "]", opener.end())
            end = len(src) if close < 0 else close + len(opener.group(1)) + 2
            out.append(string(src[i:end]))
        elif src[i] in "\"'":
            end = string_end(src, i, "\\", multiline=False)
            out.append(string(src[i:end]))
        else:
            end = i + 1
            out.append(src[i])
        i = end
    return "".join(out)


def strip_ps1_comments(src):
    out, i = [], 0
    while i < len(src):
        here = re.match(r"@(['\"])\r?\n", src[i:i + 4])
        if src.startswith("<#", i):
            close = src.find("#>", i + 2)
            end = len(src) if close < 0 else close + 2
            out.append(blank(src[i:end]))
        elif here:
            close = re.compile(r"\n" + here.group(1) + "@").search(src, i)
            end = len(src) if not close else close.end()
            out.append(src[i:end])
        elif src[i] == "#" and (i == 0 or src[i - 1] in " \t\r\n;({}|"):
            end = src.find("\n", i)
            end = len(src) if end < 0 else end
            out.append(blank(src[i:end]))
        elif src[i] == "'":
            end = string_end(src, i, None, multiline=True)
            out.append(src[i:end])
        elif src[i] == '"':
            end = string_end(src, i, "`", multiline=True)
            out.append(src[i:end])
        else:
            end = i + 1
            out.append(src[i])
        i = end
    return "".join(out)


def regex_may_start(before):
    """Whether a / after this code starts a regex literal rather than a division."""
    before = before.rstrip()
    return not before or before[-1] in "(,=:[!&|?{};+-*%<>~^" or re.search(r"\b(?:return|typeof|case)$", before)


def strip_js_comments(src):
    out, i = [], 0
    while i < len(src):
        if src.startswith("//", i):
            end = src.find("\n", i)
            end = len(src) if end < 0 else end
            out.append(blank(src[i:end]))
        elif src.startswith("/*", i):
            close = src.find("*/", i + 2)
            end = len(src) if close < 0 else close + 2
            out.append(blank(src[i:end]))
        elif src[i] in "\"'`":
            end = string_end(src, i, "\\", multiline=src[i] == "`")
            out.append(src[i:end])
        elif src[i] == "/" and regex_may_start("".join(out[-40:])):
            j, in_class = i + 1, False
            while j < len(src) and src[j] != "\n":
                if src[j] == "\\":
                    j += 1
                elif src[j] == "[":
                    in_class = True
                elif src[j] == "]":
                    in_class = False
                elif src[j] == "/" and not in_class:
                    j += 1
                    break
                j += 1
            end = re.compile(r"[a-z]*").match(src, j).end()
            out.append(src[i:end])
        else:
            end = i + 1
            out.append(src[i])
        i = end
    return "".join(out)


STRIP = {".lua": strip_lua_comments, ".ps1": strip_ps1_comments, ".js": strip_js_comments}
CALLS = {".lua": LUA_CALLS, ".ps1": PS1_CALLS, ".js": JS_CALLS}


def calls(path, src):
    """{call: how many times the code (comments left out) names it}."""
    suffix = Path(path).suffix
    src = src.replace("\r\n", "\n")  # as the zip has it, whichever way git checked the file out
    code = STRIP[suffix](src)
    found = Counter()
    for name, pattern in CALLS[suffix] + NETWORK_CALLS:
        found[name] += len(re.findall(pattern, code))
    if suffix == ".lua":
        found.update("lfs." + fn for fn in re.findall(r"\blfs\.(\w+)", code))
        named = re.findall(r"\brequire\s*[(,]?\s*[\"']([^\"']+)[\"']", code)  # require("x"), pcall(require, "x")
        found.update("require " + m for m in named if m != "hbuc" and not m.startswith("hbuc."))
        found["require (not a literal name)"] += len(re.findall(r"\brequire\b", code)) - len(named)
        # Dorico's own commands that write files: File.Save and File.Export.Text, for example
        found.update("command " + c for c in re.findall(r"[\"'](File\.[A-Za-z.]+)[\"']", code))
        # os, io, package and debug only as os.execute and the like, so every use is one of the names above
        bare = strip_lua_comments(src, keep_strings=False)
        for lib in ("os", "io", "package", "debug"):
            found[lib + " as a value"] += len(re.findall(r"(?<![\w.:])" + lib + r"\b(?!\s*\.)", bare))
    elif suffix == ".js":
        found.update("ObjC.import " + m for m in re.findall(r"\bObjC\.import\s*\(\s*[\"'](\w+)", code))
    elif suffix == ".ps1":
        found.update("IO.File." + m for m in re.findall(r"(?i)\[(?:System\.)?IO\.File\]::(\w+)", code))
    return +found


def shipped_files():
    """(path on disk, path in the zip) for each Lua, PowerShell and JavaScript file the release zip holds."""
    return [(disk, name) for disk, name in package.files() if Path(disk).suffix in STRIP]


def shipped():
    return [(name, calls(name, Path(disk).read_text(encoding="utf-8"))) for disk, name in shipped_files()]


class StripTests(unittest.TestCase):
    def test_lua_line_comment_is_not_code(self):
        self.assertEqual(calls("a.lua", 'x = 1 -- os.execute("rm")\n'), Counter())

    def test_lua_long_comment_is_not_code(self):
        self.assertEqual(calls("a.lua", "--[==[ os.execute ]==] y()\n"), Counter())

    def test_dashes_in_a_string_are_code(self):
        self.assertEqual(calls("a.lua", 's = "--" os.execute(s)\n')["os.execute"], 1)

    def test_long_string_keeps_what_follows(self):
        self.assertEqual(calls("a.lua", "s = [[--]] os.remove(p)\n")["os.remove"], 1)

    def test_crlf_counts_the_same(self):
        src = 's = "--" os.execute(s) -- os.remove\n'
        self.assertEqual(calls("a.lua", src.replace("\n", "\r\n")), calls("a.lua", src))

    def test_newlines_survive(self):
        src = "a()\n--[[\nx\n]]\nb()\n"
        self.assertEqual(strip_lua_comments(src).count("\n"), src.count("\n"))

    def test_package_loaded_is_not_load(self):
        self.assertEqual(calls("a.lua", 'package.loaded["x"] = nil\n'), Counter())

    def test_require_through_pcall_is_named(self):
        self.assertEqual(calls("a.lua", 'local ok, m = pcall(require, "lfs")\n'), Counter({"require lfs": 1}))

    def test_crlf_continuation_counts_the_same(self):
        # a backslash-newline inside a string must not end the string early on a CRLF checkout
        src = 's = "a\\\n -- b" os.execute(s)\n'
        self.assertEqual(calls("a.lua", src.replace("\n", "\r\n")), calls("a.lua", src))
        self.assertEqual(calls("a.lua", src)["os.execute"], 1)

    def test_lua_io_redirection_is_counted(self):
        found = calls("a.lua", 'io.output("f") io.input("g") local t = io.tmpfile()\n')
        self.assertEqual(found, Counter({"io.output": 1, "io.input": 1, "io.tmpfile": 1}))

    def test_lua_library_used_as_a_value_is_counted(self):
        self.assertEqual(calls("a.lua", 'local x = os; x.execute("y")\n')["os as a value"], 1)
        self.assertEqual(calls("a.lua", 'os["execute"]("y")\n')["os as a value"], 1)
        self.assertEqual(calls("a.lua", 'package.loaded.x = nil; debug.getinfo(1)\n'), Counter())

    def test_dorico_file_commands_are_counted(self):
        src = 'doc.command(app, log, "File.Save") commands.build("File.Export.Text", {})\n'
        self.assertEqual(calls("a.lua", src), Counter({"command File.Save": 1, "command File.Export.Text": 1}))

    def test_ps1_process_starts_are_counted(self):
        found = calls("a.ps1", '[Diagnostics.Process]::Start("x")\nstart notepad\nInvoke-Item a\nStart-Job {}\n'
                               'Invoke-Command {}\n')
        self.assertEqual(found, Counter({"Diagnostics.Process": 1, "start": 1, "Invoke-Item": 1, "Start-Job": 1,
                                         "Invoke-Command": 1}))

    def test_ps1_dotnet_networking_is_network(self):
        found = calls("a.ps1", "[System.Net.WebRequest]::Create($u)\n[Net.HttpWebRequest]$r = $null\n"
                               "Start-BitsTransfer -Source $u\n")
        self.assertEqual(found, Counter({"System.Net": 2, "Start-BitsTransfer": 1}))
        self.assertTrue(set(found) <= set(NETWORK))

    def test_jxa_workspace_applescript_and_urls_are_counted(self):
        found = calls("a.js", '$.NSWorkspace.sharedWorkspace.openURL(u); $.NSAppleScript.alloc; $.NSURL.URLWithString("x");\n')
        self.assertEqual(found, Counter({"NSWorkspace": 1, "NSAppleScript": 1, "NSURL": 1}))
        self.assertIn("NSURL", NETWORK)

    def test_ps1_comments_are_not_code(self):
        src = "# Start-Process x\n<# Invoke-WebRequest #>\nAdd-Type -AssemblyName X\n"
        self.assertEqual(calls("a.ps1", src), Counter({"Add-Type": 1}))

    def test_js_comments_are_not_code(self):
        self.assertEqual(calls("a.js", '// doShellScript\n/* NSTask */ const u = "a//b";\n'), Counter())

    def test_js_regex_with_a_quote_is_not_a_string(self):
        self.assertEqual(calls("a.js", "s = t.replace(/\"/g, 'x'); // NSTask\n"), Counter())


class ShippedTests(unittest.TestCase):
    def test_shipped_calls_match_the_allow_list(self):
        for zip_path, found in shipped():
            self.assertEqual(dict(found), ALLOWED.get(zip_path, {}), zip_path)

    def test_allow_list_names_only_shipped_files(self):
        self.assertLessEqual(set(ALLOWED), {zip_path for zip_path, _ in shipped()})

    def test_no_network_calls(self):
        for zip_path, found in shipped():
            self.assertFalse({name: n for name, n in found.items() if name in NETWORK}, zip_path)

    def test_security_md_names_every_process(self):
        security = (ROOT / "SECURITY.md").read_text(encoding="utf-8")
        for command in PROCESSES:
            self.assertIn(command, security)

    def test_every_process_is_in_the_code(self):
        code = "\n".join(STRIP[Path(disk).suffix](Path(disk).read_text(encoding="utf-8").replace("\r\n", "\n"))
                         for disk, _ in shipped_files())
        for command in PROCESSES:
            self.assertIn(command, code)


if __name__ == "__main__":
    unittest.main()
