# Security

Handbells Used Chart runs inside Dorico and works on the project you have open. It doesn't connect to the internet
or install anything, and outside the open project it only writes to its own two folders. This page says exactly what it
runs and which files it uses, how to check that a download is genuine, and how the repository guards against unsafe
changes.

## Reporting a vulnerability

Please report it privately. Open the repository's
[Security tab](https://github.com/ThePrismSystem/handbells-used-chart-dorico-plugin/security), choose **Report a
vulnerability**, and describe what you found. Please don't open a public issue for it. I'll reply as soon as I can.

Fixes go into the latest release.

## What a run does

When you choose **Script > Handbells Used Chart**:

1. The plug-in checks the Dorico version, that the project has been saved, and that the full score is open. It then
   reads the music and shows its dialog. To read noteheads and colours, it has Dorico save a copy of the project
   into the plug-in's temp folder, reads the copy and deletes it. The project, its file and its undo history stay as
   they were, and nothing in the project changes before you click OK.
2. If you click Cancel, the run ends there.
3. If you click OK, it remembers your choices and saves the project. Then it draws or updates the chart, or removes
   it, and sets the full-score layout options listed under
   [Known limitations](README.md#known-limitations) in the README. The save comes first, so File > Revert takes the
   whole run back.

## Programs it starts

The plug-in starts nothing but its dialog script and, on a Mac, two standard commands.

[`tests/test_shipped_calls.py`](tests/test_shipped_calls.py) reads every Lua, PowerShell and JavaScript file in the
release zip. It counts the calls that start a program, read or write a file, load code, call Windows directly or use
the network, and the counts must match a list kept in the test, with a reason for each entry. So the test fails when
one of those calls is added or removed. It matches the names those calls go by, which catches ordinary code; code
written on purpose to disguise a call could still get past it.

Each path is quoted for the shell that runs the command: cmd on Windows, sh on a Mac.

### On Windows

The dialog and the results window are drawn by Windows PowerShell 5.1, which comes with Windows:

```
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<plug-in>\dialog\windows.ps1" -Request "<temp>\request.json" -Response "<temp>\response.json"
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<plug-in>\dialog\windows.ps1" -Message "<temp>\message.json"
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<plug-in>\dialog\windows.ps1" -Choice "<temp>\choice.json" -Response "<temp>\response.json"
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<plug-in>\dialog\windows.ps1" -Pick "<temp>\pick.json" -Response "<temp>\response.json"
```

The last two run only when the score has noteheads changed in Dorico: `-Choice` is the message that asks for a
MusicXML export, and `-Pick` the file picker.

The options do the following:

- `-NoProfile` skips your PowerShell profile scripts, so nothing of yours runs alongside the dialog or changes how it
  behaves.
- `-ExecutionPolicy Bypass` lets this one PowerShell process run the script. It doesn't change the execution policy
  for your account or your computer, and it ends when the dialog closes. The plug-in needs it because the default
  policy on Windows desktops, Restricted, runs no script files at all, signed or not. (`windows.ps1` isn't signed.)
- `-WindowStyle Hidden` hides PowerShell's console window. The dialog itself is an ordinary window.
- `-File` runs that one script, with the arguments that follow it.

[`dialog/windows.ps1`](plugin/Handbells%20Used%20Chart/dialog/windows.ps1) loads Windows Forms and System.Drawing,
which are part of Windows, to draw the window. It also declares one Windows function, `SetProcessDPIAware` from
`user32.dll`, so the window is drawn sharp on a scaled display. It reads the request file, shows the dialog and writes
your choices to the response file. For the results window, it reads the message file and writes nothing. For the
MusicXML message, it writes the button you pressed; for the picker, Windows' own Open dialog, it writes the paths
you chose and opens nothing.

### On a Mac

The dialog is drawn by `osascript`, macOS's own script runner, with JavaScript for Automation:

```
/usr/bin/osascript -l JavaScript '<plug-in>/dialog/mac.js' '<temp>/request.json' '<temp>/response.json' 2>'<temp>/osascript.log'
/usr/bin/osascript -l JavaScript '<plug-in>/dialog/mac.js' --message '<temp>/message.json' 2>'<temp>/osascript.log'
/usr/bin/osascript -l JavaScript '<plug-in>/dialog/mac.js' --choice '<temp>/choice.json' '<temp>/response.json' 2>'<temp>/osascript.log'
/usr/bin/osascript -l JavaScript '<plug-in>/dialog/mac.js' --pick '<temp>/pick.json' '<temp>/response.json' 2>'<temp>/osascript.log'
```

[`dialog/mac.js`](plugin/Handbells%20Used%20Chart/dialog/mac.js) uses Cocoa to draw the window. Like the Windows
script, it reads the request file and writes the response file, or reads the message file. The `--choice` and
`--pick` modes are the MusicXML message and the file picker. The picker is macOS's own Choose File dialog, from
`osascript`'s Standard Additions; it hands back the paths you chose and opens nothing.

Two more commands can run on a Mac:

- `/bin/mkdir -p '<folder>'` makes the plug-in's data and temp folders when Dorico's Lua has no LuaFileSystem
  library. Dorico has it on Windows, where the folders are made through it instead.
- `/bin/sleep 1` waits a second at a time, but only if `osascript` comes back before you have answered the dialog.

## Files it reads and writes

- The plug-in's own folder, which it reads.
- Its data folder, `%APPDATA%\Handbells Used Chart\` on Windows and
  `~/Library/Application Support/Handbells Used Chart/` on a Mac. `settings.json` remembers your choices. `run.log`
  records the latest run; it's emptied when a run starts.
- Its temp folder, `%TEMP%\hbuc\` on Windows and `$TMPDIR/hbuc/` on a Mac (`/tmp/hbuc/` if `TMPDIR` isn't set),
  which holds:
  - the dialog's request, response and message files, and the MusicXML message's and picker's;
  - Dorico's text exports of the project, which the plug-in reads to find the project's file, an existing chart, the
    flow headings and whether flows start on a new page;
  - `reading.dorico`, a copy of the open project that Dorico saves there so the plug-in can read each note's notehead
    and colour from it. The plug-in deletes it once it has read it;
  - `osascript.log` on a Mac;
  - the log of a run that couldn't start, which goes in `hbuc` under the first of `TEMP`, `TMP` and `TMPDIR` that is
    set (on a Mac with none of them set, `/tmp/hbuc/`).
- The open project, which it saves before it changes anything.
- Only when the score has noteheads changed in Dorico:
  - the MusicXML files you choose in the picker, which it reads;
  - the project's folder, whose `Flows from …` folders it lists (names, times and sizes) to find the export Dorico
    has just written there. Dorico writes the export itself, where its export dialog says.

[`hbuc/guards.lua`](plugin/Handbells%20Used%20Chart/hbuc/guards.lua) decides where the folders are. The plug-in
writes its files in `hbuc/dorico/files.lua`, `safe.lua` and `dialog.lua`, and reads the MusicXML files through
`files.lua` too. Dorico writes the text exports when `hbuc/dorico/doc.lua` runs File > Export > Text, writes a
MusicXML export when `hbuc/dorico/musicxmlstep.lua` runs File > Export with MusicXML chosen, saves the project when
`hbuc/main.lua` runs File > Save, and saves the copy in the temp folder when `hbuc/dorico/savedcopy.lua` calls
`app:save`. The call test pins each of these calls.

## No network

None of the plug-in's code opens a network connection, downloads anything, or contains a web address.
`tests/test_shipped_calls.py` fails if any of it names a networking API (PowerShell's web cmdlets, .NET's
`System.Net`, Cocoa's `NSURL` classes, a socket library), `curl` or `wget`, or a web address.

## What the repository checks

| Check | What it covers | Where it runs |
|---|---|---|
| Unit tests | the plug-in's logic, the Mac dialog's testable parts, and the tools | `test` workflow; `python tools/run_tests.py` |
| `tests/test_shipped_calls.py` | every command, file call and network call in the release zip's code | with the unit tests |
| luacheck | Lua | `lint` workflow; `python tools/lint.py` |
| PSScriptAnalyzer, with the InjectionHunter rules | PowerShell | `lint` workflow; `python tools/lint.py` |
| ESLint | JavaScript | `lint` workflow; `python tools/lint.py` |
| ruff, with its security rules | Python | `lint` workflow; `python tools/lint.py` |
| zizmor | the GitHub Actions workflows and Dependabot's settings | `lint` workflow; `python tools/lint.py` |
| gitleaks | secrets anywhere in the git history | `lint` workflow; `python tools/lint.py` |
| CodeQL, `security-extended` queries | JavaScript, Python and the workflows | `codeql` workflow on every pull request, every push to `main`, and weekly; `python tools/lint.py --codeql` |
| Secret scanning with push protection | every push | GitHub |
| Dependabot | alerts for known vulnerabilities, and updates to the actions and development tools | GitHub |

CodeQL, PSScriptAnalyzer, zizmor and gitleaks report to the Security tab's code scanning page. CodeQL can't read Lua
or PowerShell, so those get their linters and the call test instead.

`python tools/lint.py` runs every tool it finds and says how to install the ones it doesn't.

## Checking a download

Each release zip is built on GitHub by the repository's release workflow, from a tagged commit, and GitHub signs a
record of that build (an attestation). With the [GitHub CLI](https://cli.github.com/) installed, run:

```
gh attestation verify handbells-used-chart-dorico-v<version>.zip --repo ThePrismSystem/handbells-used-chart-dorico-plugin --signer-workflow ThePrismSystem/handbells-used-chart-dorico-plugin/.github/workflows/release.yml
gh release verify-asset v<version> handbells-used-chart-dorico-v<version>.zip --repo ThePrismSystem/handbells-used-chart-dorico-plugin
```

The first command checks that the repository's release workflow, `.github/workflows/release.yml`, built the zip,
and shows which commit it came from. The second
checks that it's the file attached to that release.

Without the CLI, compare the zip's SHA-256 with the one in the release notes. Use
`certutil -hashfile <zip> SHA256` on Windows, or `shasum -a 256 <zip>` on a Mac.

## How the repository is protected

- Changes reach `main` only through pull requests whose checks pass, and every commit on `main` must be signed. Force
  pushes to `main` and deleting it are blocked.
- Release tags (`v*`) can't be moved or deleted.
- Releases are immutable: once one is published, its zip and its tag can't be changed.
- Workflows get a read-only token unless a job needs more, and every action is pinned to a commit. Workflows from
  outside contributors wait for approval before they run.

## What isn't in the zip

`tools/`, `tests/`, `spike/` and `fixtures/` are for developing the plug-in, and the release zip leaves them out.
They drive Dorico on a developer's own computer: they talk to Dorico's Remote Control API on `127.0.0.1`, and they
click through its windows with UI Automation and Win32 calls. None of them runs when you use the plug-in.
