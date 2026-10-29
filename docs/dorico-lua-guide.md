# Writing Lua plug-ins for Dorico 6

A field guide to the parts of Dorico 6's Lua scripting that Steinberg doesn't document, written while building the
Handbells Used Chart plug-in. It covers how the plug-in reads the music, draws into the score, shows a dialog, and is
tested from outside Dorico, and the workarounds and gotchas found along the way.

It is based on Dorico 6.2.30 on Windows 11, probed script by script, and the probes are in `spike/`. The Mac parts
(section 8) are written but haven't run on a Mac yet. None of this is a published API: Steinberg can change any of
it in any update, so check each call on the version you target.

## Contents

1. [How a plug-in runs](#1-how-a-plug-in-runs)
2. [The object model, as far as we mapped it](#2-the-object-model-as-far-as-we-mapped-it)
3. [Reading the music](#3-reading-the-music)
4. [The text export](#4-the-text-export)
5. [Changing the score](#5-changing-the-score)
6. [Commands](#6-commands)
7. [Undo, redo and saving](#7-undo-redo-and-saving)
8. [A dialog from Lua](#8-a-dialog-from-lua)
9. [Testing from outside Dorico](#9-testing-from-outside-dorico)
10. [Gotchas, in one list](#10-gotchas-in-one-list)
11. [Where to look in this repository](#11-where-to-look-in-this-repository)

## 1. How a plug-in runs

### Where scripts go

Dorico lists every `.lua` file at the top level of its Script Plug-ins folder in the **Script** menu, under the file's
name:

- Windows: `%APPDATA%\Steinberg\Dorico 6\Script Plug-ins\`
- Mac: `~/Library/Application Support/Steinberg/Dorico 6/Script Plug-ins/` (not yet confirmed on a Mac)

It doesn't look in subfolders, so a plug-in made of several modules puts one entry file at the top level and its
modules in a folder beside it. The entry file finds that folder from its own path:

```lua
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local root = here .. "My Plug-in/"
```

### One Lua state for the whole session

Dorico keeps a single Lua state from launch to quit. Globals and `package.loaded` survive from one script run to the
next. Two things follow:

- Clear your own modules at the start of every run. Otherwise `require` hands back the version loaded by an
  earlier run, and edits to a module (or an updated install) don't take effect until Dorico restarts.
- Add to `package.path` only once. Prepending your folder on every run makes the path grow without end.

```lua
for name in pairs(package.loaded) do
  if name:match("^myplugin") then package.loaded[name] = nil end
end
local mine = root .. "?.lua"
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
```

A global you set is still there next run, which is handy for passing values between runs and dangerous if you forget
it. Clear what you set.

### Errors are quiet

- **A script with a syntax error is skipped without a word.** Dorico doesn't run it, log it or report it. Run
  `luac -p` (Lua 5.2's compiler) over every file before trying a change in Dorico.
- **An uncaught runtime error ends the script.** `Script.RunScript` has a `ShowConsole` parameter, which suggests a
  console that can show such errors, but a plug-in can't count on the user seeing anything. Wrap the whole run in
  `pcall` or `xpcall`, log the traceback to a file, and tell the user in your own window.
- `debug.traceback(err)` returns a non-string error unchanged, with no traceback. Turn tables into text first if you
  throw error tables.

### What Lua has

- Lua 5.2, with the standard `io`, `os`, `string`, `table`, `math` and `debug` libraries.
- On Windows, `require("lfs")` (LuaFileSystem) works: Dorico ships `lfs.dll`. Whether a Mac has it is unconfirmed,
  so the plug-in works without it there.
- No user interface at all. Section 8 is how to get one.
- `os.execute` runs a command and **Dorico waits for it**, frozen, until it returns.

### Two ways in

Everything a plug-in does goes through one of two doors:

- The object model: `DoApp` and `DoCore`, C++ classes bound to Lua with luabind. It reads the score's structure
  and notes, and it can create notes, texts and players and set event properties.
- Commands: `app:doCommand("Name?Param=Value&...")`, the same commands Dorico's menus and key commands run. They
  do everything the object model can't (selections, flows, layout options, saving).

Most real tasks need both. The plug-in reads with the object model, selects with a command, then changes a property
with the object model or runs another command on the selection.

### Finding out what exists

- The bound classes are in Lua's registry. `spike/17_api_map.lua` walks it and writes every class's members to a
  file. That's how we found `NoteEvent.pitchWithSpelling`, `TextEvent.text`, `BreakEvent.isSystemBreak`,
  `EventStream.type`, `Flow.elementTables` and `Score.title`.
- Command names come from Dorico's Remote Control API (`getcommands` lists them) and from Dorico's own log, which
  records the command behind a UI action or a Remote API request. A command string Dorico logs works from Lua as it
  is.
- Everything else came from probes: small scripts that try one thing on a scratch copy and write down what
  happened.

## 2. The object model, as far as we mapped it

```lua
local app = DoApp.DoApp()
local score = app.currentScore        -- nil, or an error, when no project is open
```

| Object | What we used | What it doesn't have |
| ------ | ------------ | -------------------- |
| App | `versionString` (such as `6.2.30b6245`), `currentScore`, `currentLayoutID`, `doCommand(cmd)` | |
| Score | `flows`, `players`, `openScoreID` (for commands), `title`, `addPlayer(instrumentId, false, 1)` | the file path, any way to delete a player |
| Flow | `id`, `players`, `voiceStreams`, `staveStreams`, `allStreams`, `instruments`, `addPlayer`, `removePlayer` | a name or title |
| Player | `tostring(player)` (its name), `instruments` | an id, `==` |
| Instrument | `id` | a name (`tostring` and `.name` throw), its type, its transposition |
| EventStream | `events`, `dump()`, `blockInstances`, `createNote`, `createText`, `delete`, `deleteEventsInRange`, `type`, `id` | |
| Block instance | `id` (the dump's "Start block id"), `block.id` (what `EventEdit.Select` takes) | |
| Event | `id`, `propertyTable`, `tostring(event)` | |
| Layout | `id`, `players`, `addPlayer`, `removeFlow` | any layout option |

Things Lua can't read at all, and what the plug-in does instead:

| Missing | Workaround |
| ------- | ---------- |
| A player's id (commands need it) | Rename each candidate id to a unique token and see which player takes it (section 5) |
| Layout options | Set them by command. To learn a value, compare text exports taken under each candidate (section 4) |
| The project's file path | The text export's `Path` column |
| A flow's name | The text export's `FlowName` column, or the Remote API's `getflows` |
| An instrument's name | The text export's `Instrument` column |
| Which instrument a voice stream belongs to | `flow.instruments[i]` owns `flow.voiceStreams[i]` |
| The selection, or an event looked up by id | Keep the ids you need from `dump()` and select them by command |
| An instrument's type or transposition | Ask the user |

### Ids and identity

- **Players have no `==`.** Comparing two throws "No such operator defined". Compare `player.instruments[1].id`,
  which is unique and stable.
- **Player ids are not instrument ids.** Commands such as `Project.Player.Rename` take a *player* id, which Lua
  doesn't expose. In a fresh project a player's id often equals its first instrument's id. In Steinberg's own Smith
  example it doesn't, so don't rely on it.
- **`flow.instruments[i].id` owns `flow.voiceStreams[i]`:** one entry per voice stream, in the same order. This held
  on every project we tried, including a piano with six voices on two staves. `flow.instruments[i].streams` looks
  like the obvious route, but it returns streams only for the first instrument and an empty list for the rest.
- Stream `type` is 0 for a timebase stream, 1 for a stave, 2 for a voice and 3 for a player.

### Properties

Events carry their details in a property table, read and written through `DoCore` values:

```lua
local ctx = DoCore.PropertyContext()
local head = tostring(note.propertyTable:get("kNoteheadSetOverride", ctx))   -- "" when not set
note.propertyTable:set("kNoteHideStem", DoCore.Variant.createString("true"), ctx)
```

- `get` returns a Variant, and `tostring(variant)` gives its value. An unset property reads as `""`.
- `getPropertyNames()` lists only the properties an event actually has, not every one it could have.
- A colour set by command, which includes the Properties panel, can't be read. `get("kEventColour", ctx)` returns an
  invalid Variant (`type` -1) whose text is `""`, the same as no colour. The note still lists `kEventColour` in
  `getPropertyNames()`, so you can tell "coloured, but unreadable" from "no colour". A colour set from Lua reads back
  as it was set, after a save and reopen and in a pasted copy too.
- A notehead set chosen in Dorico (the Notations menu, the Properties panel, or the command
  `Edit.SetNoteheadSetOverride?NoteheadSetEntityID=…`) can't be read either. `kNoteheadSetOverride` is listed and
  reads as an invalid Variant, in the music and in a pasted copy alike. The Variant's `toString()` is `""` and its
  `toInt()` throws, and every such Variant compares equal (`==`) to every other, whatever the set and even to an
  unset one, so you can't even group the notes. Giving a note the set it already has, by command, leaves the value
  Lua set: clear it first (`Edit.ClearNoteheadSetOverride`) to get the unreadable kind. This plug-in reads such
  notes' noteheads from a MusicXML export instead (section 5, "Exporting MusicXML").
- A read can lag the page. After a command recoloured a note whose colour had been set from Lua, the page showed the
  new colour while Lua still read the old one.
- `set` returns `true` when Dorico took the value. That doesn't always mean the score changed (section 5).

## 3. Reading the music

### `tostring(event)` and pitch

An event's `tostring` gives its kind, id, position and, for notes, the **sounding** spelling:

```
kNoteEvent (id:195) at 4, duration 1  G#5 (ends 5)
kGraceNoteEvent (id:200) at 8  secondary pos -1/2 (-0.5), notated duration: 1/2 (0.5), B6
kNoteEvent (id:981) at 13/2 (6.5), duration 1/2 (0.5)  Bb4 (ends 7)
```

- Positions and durations are in quarter notes, as an exact fraction followed by a rounded decimal in brackets. Read
  the fraction: `1/3 (0.333333)` is a third, not 0.333333.
- A double sharp is spelled `x` (`Fx4`), a double flat `bb`.
- A grace note is its own event kind, at the position of the note it leads into.
- `propertyTable:get("kNotePitch", ctx)` is the sounding MIDI pitch.
- **Every pitch you can read is sounding.** A written C4 on Dorico's Handbells instrument reads as C5 (pitch 72).
  Nothing in Lua says how an instrument transposes, so a plug-in that needs written pitch has to know the
  instrument's transposition some other way. This one asks the user, per instrument.

### `stream.events` fails on real music

`stream.events` lists a voice stream's events as Lua objects, which is what you want. On real music, it throws
"Not implemented" for any stream that holds an event kind with no Lua class: lyrics, slurs, hairpins and other
lines, arpeggios, and playing techniques. Handbell parts are full of playing techniques, so it fails on almost every
real score. `stream.blockInstances[i].events` fails the same way. It can also silently list fewer events than the
stream holds.

### `stream:dump()` always works

`stream:dump()` returns text listing every event, whatever its kind:

```
Start block id: 1010 position: 0
16 (16) dur: 1: kNoteEvent (id:209) at 16, duration 1  C5 (ends 17)
8 (8): kGraceNoteEvent (id:200) at 8  secondary pos -1/2 (-0.5), notated duration: 1/2 (0.5), B6
```

Each event line is `<position> (<position>)[ dur: <duration>]: <tostring(event)>`. A text event's own line breaks
continue it on further lines, ending with a line holding its paragraph style in brackets. The dump gives every
note's id, position and sounding spelling. It shows no properties, so it can't tell you noteheads or colours. Note
the `Start block id`: despite its name it is a block *instance* id, and the events after it belong to that
instance. You need the instance's block to select an event by command (section 5).

The plug-in parses dumps with `hbuc/dump.lua` and event strings with `hbuc/eventtext.lua`. Both are pure Lua, with
unit tests.

### Noteheads and colours: read a pasted copy

To read properties from a stream that `stream.events` refuses, the plug-in copies the music into a scratch flow that
holds only notes, reads that, and takes it away again:

1. `Project.Flow.New` adds a flow at the end. It holds every player, so remove the players the music flow doesn't
   have with `flow:removePlayer`.
2. Select the music flow's whole range: `EventEdit.Select` its first event, then `Edit.SelectToStartOfFlow`,
   `Edit.SelectAtEndOfFlow`, and `EventEdit.NavigateDownExtend` once for each staff after the first
   (`#flow.staveStreams - 1`).
3. `Filter.NotesAndChords`, then `Edit.Copy`.
4. In the scratch flow, create a temporary note at position 0 on the staff the copied range starts on,
   `EventEdit.Select` it, and `Edit.Paste`. The range starts on the staff of the event you selected, which is
   lower down when the first players have nothing to play. Pasted on the top staff instead, every staff's notes land
   that much higher, under the wrong player. The scratch flow has one voice per staff, and a grand staff's voices
   are `[treble, bass]`, so take the scratch voice of the same instrument and staff.
5. The filter keeps note-attached lines with their notes, and a line makes `stream.events` throw again. Delete every
   event in the scratch flow whose kind has no Lua class: select each by id from the dump, then `Edit.Delete`.
6. Now `stream.events` and `propertyTable:get` work: noteheads, colours and grace notes. Skip the temporary note by
   its id.
7. Take the scratch flow away with **one** `Edit.Undo` (section 7 explains why exactly one).

It takes about 2 seconds a flow. Two catches:

- The paste merges unisons in two voices on one staff. They're the same pitch, so compare the *set* of
  (instrument, spelling) pairs with the dumps rather than counting notes.
- It replaces the clipboard and the selection. Tell users.

The plug-in tries `stream.events` first and only copies a flow whose events can't be read directly, or whose counts
disagree with the dump (`hbuc/dorico/readscore.lua`).

## 4. The text export

```lua
app:doCommand("File.Export.Text?File=C:/temp/out.txt&Show=false")   -- writes C:/temp/out.csv
```

`File.Export.Text` writes a CSV of every text in the project, silently, next to the name you give it (with `.csv` in
place of `.txt`). Its columns are `Path, ID, FlowNumber, FlowName, Instrument, Page, Bar, Type, Text, Hidden`. The
plug-in uses it for four things Lua can't read:

- Whether the project has been saved. `Path` is empty until the project is saved, then holds its file path. No
  Lua property gives the path.
- Flow titles. The `Flow Info (Title)` rows give each flow's title, by `FlowNumber`.
- Instrument names. Put a marker text in each voice stream with `stream:createText`, export, read each marker
  row's `Instrument` column (the `ID` column is `<flow>-<stream>-<event>`), then delete the markers with
  `stream:delete`. Making and deleting the markers still leaves an undo step, one that changes nothing (section 7).
- Layout options, indirectly. Lua can set layout options but not read them. To learn `flowHeadingBehaviour`,
  export once, then export again under each candidate value. The flow headings appear as `Text Frame` rows only when
  headings show, so the candidate whose rows match the first export is the value the project had. Put that value
  back afterwards. (With a single flow, two of the three values look the same, so this needs two or more flows.)
  `flowBreakBehaviour` works the same way with every row's `Page`: under `kNoFlowBreaks` a second flow's items move
  up onto the first flow's page. Music with no texts may export nothing that moves, so put a temporary text at the
  start of the second flow (`stream:createText`, then `stream:delete` on the event it returns), and run the check
  while the first flow is short: if it fills its page, both values start the second flow on a new page. When the
  exports are still identical, nothing tells the values apart, so assume Dorico's default, `kStartNewPageForFlows`.

Quirks:

- Some projects export their flow titles with no `FlowNumber` or `FlowName`, in alphabetical order (Steinberg's
  Smith example). Then you only know the set of titles, not which flow has which.
- That same project exported no hidden texts at all, so don't rely on finding a hidden marker in the export.
- Text fields can hold quoted newlines. Use a CSV reader that understands quotes, not a line-by-line split.
- Read a missing column as empty rather than crashing, and skip blank lines.

## 5. Changing the score

### Notes

```lua
local RL = DoCore.RhythmicLength
voice:createNote(RL(4), RL(1), DoCore.MIDIPitchWithSpelling.fromString("Ab5"))
```

- `fromString` takes a sounding spelling, `<letter><accidentals><octave>`, and the note keeps exactly that
  spelling. On a transposing instrument, add the transposition: on Handbells (+12), `"C5"` shows as a written C4.
- **A constructor given bad arguments can crash Dorico.** Never pass `fromString` a pitch above MIDI 127, or anything
  you haven't checked parses. Validate before every call.
- Two `createNote` calls at one position make a chord. A grand-staff player's `voiceStreams` are
  `[treble voice, bass voice]`, and a note goes on the staff of the voice it's written into.
- `voice:createText(RL(0), RL(1), "label")` makes staff text above the staff.

### Properties that work when set

| Property | Value | Effect |
| -------- | ----- | ------ |
| `kNoteHideStem` | `"true"` | hides the stem |
| `kNoteheadSetOverride` | a set id, such as `noteheadset.diamondNoteheads` | draws the note in that notehead set |
| `kEventColour` | `#rrggbb` | colours the note |
| `kTextHide` | `"true"` | hides a text (it shows as a signpost in Write mode, and doesn't print) |
| `kTimeSignatureHide` | `"true"`, on the bar-division event | hides a time signature |
| `kNoteHideNotehead`, `kNoteLedgerLineHide` | `"true"` | with a hidden stem, makes an invisible note |

Set them with `DoCore.Variant.createString(...)`. Notehead set ids we used: `noteheadset.default`,
`noteheadset.diamondNoteheads`, `noteheadset.rectangular`, `noteheadset.triangleUpNoteheads`,
`noteheadset.triangleDownNoteheads`, `noteheadset.Xnoteheads`.

### Properties that don't work when set

- `kEventHide` hides neither texts nor rests. Use `kTextHide` for texts. For rests, don't create them: remove
  them by command.
- Naturals can't be hidden by setting a property. `kNoteAccidentalVisibility` takes the value and nothing
  changes. What works: select the note and run `Edit.HideAccidental`, once per note.

### Selecting an event for a command

```
EventEdit.Select?FlowID=<flow.id>&EventID=<event.id>&EventBlockID=<block id>
```

The block id is the id of the block holding the event. Find the event's instance (the `Start block id` above it in
the dump) in `stream.blockInstances`, and take that instance's `block.id`:

```lua
for _, bi in ipairs(stream.blockInstances) do
  if bi.id == instanceId then return bi.block.id end
end
```

In most projects the block id happens to be the instance id minus 1000, and the plug-in once took that for the rule.
In a downloaded arrangement, instance 1061 held block 36. A select given the wrong block id selects nothing and
reports no error, so the commands after it act on nothing too. `hbuc/dorico/doc.lua`'s `blockIdOf` does the lookup.

`Edit.SelectNone` clears the selection, and `Edit.SelectAtEndOfFlow` extends one to the end of the flow.

### Flows

- `Project.Flow.New` adds a flow at the end, holding every player. Find it as the flow whose id wasn't there before.
- `Project.Flow.Rename?FlowID=<id>&Name=<name>` renames it.
- `Project.Flows.MoveToStart?FlowIDArray=<id>`: a single id is the whole array, as a plain number.
- `flow:removePlayer(player)` takes a player out of one flow.
- **An empty flow prints "Tacet" in every part,** since each part layout includes every flow.
  `layout:removeFlow(flow)` on each part layout prevents it.
- `stream:deleteEventsInRange(RL(0), RL(<end>))` on each of `flow.allStreams` clears a flow's notes, texts, time
  signatures and breaks, and keeps its players and its place.
- Deleting a flow needs Setup mode: `Window.SwitchMode?WindowMode=kSetupMode`, then `Project.Flows.Delete`. Dorico
  asks the user to confirm, and the command waits for the answer.

### Players

- `score:addPlayer("instrument.pitchedpercussion.handbells", false, 1)` adds a player and returns it. It joins every
  flow, so remove it from the ones it shouldn't be in. Dorico also makes a part layout for it.
- **Finding a player's id.** Rename each candidate id in turn to a unique token with
  `Project.Player.Rename?PlayerID=<id>&Name=<token>`, see which player's `tostring` becomes the token, then give it its
  name back. Pass `Name` alone so the short name isn't touched.
- **Staff labels show instrument names,** so renaming a player doesn't change them, and instrument names can only be
  set through Dorico's Edit Instrument Names dialog. To hide a player's labels, list its id in the layout option
  `staffLabelLayoutOptions.playersToShowPlayerName` and name the player with a single space.
- **A plug-in can't delete a player.** There's no `removePlayer` on the score, and `Project.Players.Delete` acts on
  the Setup-mode selection, which commands can't set. `Project.Players.DeleteEmpty` opens Dorico's "Delete Empty
  Players" dialog, which lists every player with no music, by name, for the user to confirm. A player named with a
  space shows as a blank row, so name it first. The dialog ticks the user's own empty players too.
- `Project.Layouts.Delete?LayoutIDArray=<id>` deletes a part layout silently.

### Layout and notation options

Options are set by command, in the form Dorico itself logs for the Remote API's `setoptions`:

```
Project.Layout.SetOptions?Dictionary=list: {string: "flowHeadingBehaviour"}\, {string: "kNoFlowHeadings"}&OpenScoreID=<score.openScoreID>&LayoutIDArray=<layout id>
Project.Flow.SetNotationOptions?Dictionary=list: {string: "barlineOptions.finalBarlineType"}\, {string: "kNone"}&OpenScoreID=<id>&FlowIDArray=<flow id>
```

- The dictionary alternates path and value items, separated by `\, `. Inside an item, escape a backslash, a quote
  and a comma with a backslash (`"3\,4"` for the list 3,4).
- Always give a flow's id in `FlowIDArray`. The Remote API's `setoptions` with `flowIDs` changed flow 0 instead.
- Options we used: `flowHeadingBehaviour`, `flowBreakBehaviour` (`kStartNewPageForFlows` or `kNoFlowBreaks`, for the
  whole layout), `hideEmptyStavesPolicy`, `alwaysVisiblePlayers`, `staffLabelLayoutOptions.playersToShowPlayerName`,
  and per flow `barlineOptions.finalBarlineType` and `barlineOptions.defaultBarlineType`.
- Lua can't read any option back. Overwriting one loses the user's value unless you can recover it another way
  (section 4), and the plug-in tells users which options it changes.

### Layout tricks that worked

- A new flow has no time signature, so the whole flow is one bar. A system break in the middle of a bar does
  nothing. To break a system, give it a barline: select a note, run `NoteInput.CreateTimeSignature?Definition=X` (an
  open meter at that note), hide it with `kTimeSignatureHide`, then run `Edit.CreateSystemBreak` with the note still
  selected. `createSystemBreak` from Lua makes a break event that doesn't take effect.
- Rests: select a voice's first event, `Edit.SelectAtEndOfFlow`, then `Edit.RemoveRests`. An empty staff has no
  event to select, so put an invisible note in it first and remove the rests from there. After an update, one bar
  rest survived the sweep. Selecting the rest itself and running `Edit.RemoveRests` again removed it.
- To show only some staves on a system, set `hideEmptyStavesPolicy = kAllSystems` with every player who must always
  show in `alwaysVisiblePlayers`.

### Exporting MusicXML

There's no silent export, but a script can open Dorico's own MusicXML export and wait for it:

```lua
app:doCommand("File.Export?FilterID=MusicXMLExportFilter")   -- opens "Export MusicXML"; returns when it closes
```

- The call blocks until the dialog closes, then the script carries on. It returns `nil` whether OK or Cancel was
  pressed, so look for new files to tell them apart.
- By default the dialog exports uncompressed `.musicxml`, every flow and every layout (full score and parts) as
  separate files, into a new folder beside the project: `Flows from <title>/<project> - <layout> - <NN> <flow>.musicxml`.
  Exporting into that folder again asks, file by file, whether to overwrite.
- The export only sees the score as it was before the script run. A flow the same run made exported as an empty
  `<score-partwise/>`; made in one run and exported in the next, it came out in full.
- Pitches are written pitch, with `<transpose>` per staff (Dorico's Handbells: `octave-change` 1). Colours are
  `color="#RRGGBB"` on `<note>`.
- Of Dorico 6's 36 non-default built-in notehead sets, 17 export no `<notehead>` at all, among them Rectangular,
  Old-Style Diamond and Wide Diamond. X, Large X and Diamond, and X and Diamond all export `x`, and the four slash sets
  `slash`. Diamond exports `diamond`, White Diamond `diamond` with `filled="no"`, and the two triangles `triangle` and
  `inverted triangle`. The README of this repository has the whole list.
- Positions worked out from `divisions`, `duration`, `backup`, `forward` and `chord` matched `stream:dump()`'s note for
  note on three scores, once a grace note is put at the next note's onset and a tied-over note
  (`<tie type="stop"/>`) is left out.

### Things that didn't work

- `copyRange` copies nothing, within a flow or across flows.
- There's no silent MusicXML export: `File.Export` and `File.Export.SpecificFlowsAndParts` open dialogs (but see
  "Exporting MusicXML" above).
- Saved projects are binary inside (`score.dtn`), so reading the project file isn't an option.

## 6. Commands

- Syntax: `Name?key=value&key=value`.
- Values: Dorico reads a backslash as an escape. Write `\&` for an ampersand, `\,` for a comma and `\\` for a
  backslash. A bare comma ends the value, so `Name=A, B` names a player `A`. `=` and any Unicode go through as they
  are. A line break can't be sent. Build every command with one encoder function, so a player named "Handbells
  (P&F)" or "Bells, choir 2" goes through exactly. Escape backslashes before anything else, or the escapes you add
  get doubled.
- Check what you send. Converting with `tostring` turns a missing value into the word `nil`, and a wrong id
  selects, renames or deletes the wrong thing, or nothing, with no error from Dorico. The plug-in's builders refuse a
  missing value and any id that isn't a whole number (`hbuc/commands.lua`).
- Dialogs block. A command that opens one of Dorico's dialogs waits until the user answers it, and the script
  waits with it.
- Before selecting anything, leave note input (`NoteInput.Exit`) and switch to Write mode
  (`Window.SwitchMode?WindowMode=kWriteMode`).

## 7. Undo, redo and saving

This is the gotcha that cost the most time.

- Everything a script run changes is one undo step, object-model edits included. On Dorico 6.2.30, one Edit > Undo
  after a run took back a text the run made with `createText`, and a colour it set with `propertyTable:set`.
- `Edit.Undo` inside a script rolls back everything that run has done so far, and nothing the user did before
  the run. That includes object-model edits: in a run that made a text, ran `Project.Flow.New` and made another
  text, an undo took back all three. An undo in a run that has changed nothing changes nothing.
- But only the first undo is safe. After an undo inside a run, whatever the run changes next, commands and
  object-model edits alike, joins the user's *previous* undo step. A second undo in the same run takes back the
  user's last action as well.
- A run that makes a text and deletes it again still leaves an undo step. Edit > Undo afterwards uses it up and
  changes nothing you can see. An early probe of ours saw that and concluded that object-model edits weren't
  undoable, as earlier versions of this guide said.
- The read clears the redo history. After a run that changed nothing (the user cancelled), Edit > Redo brings
  back whatever the run's undo took away.

What the plug-in does with that:

1. Read everything first, into as many scratch flows as it needs, and take them all away with exactly one
   `Edit.Undo`, before it changes anything.
2. Show the dialog. If the user cancels, stop: nothing has changed.
3. Save the project (`File.Save`) before drawing, so **File > Revert** takes the whole run back. One Edit > Undo
   takes the chart back too, its notes and layout options included (`spike/39_chart_undo.py`, Dorico 6.2.30). But
   when the run read through a copy, its `Edit.Undo` came before the drawing, so the chart joined the user's
   previous undo step and that Edit > Undo took back both.

Saving:

- `File.Save` on a saved project is silent and immediate. On a never-saved one it opens Save As, so check the text
  export's `Path` first and ask the user to save.
- To confirm a save happened, compare the file's modification time before and after (`lfs.attributes(path,
  "modification")`).

## 8. A dialog from Lua

Lua in Dorico has no windows of its own. The plug-in writes its request to a JSON file, runs an external script with
`os.execute`, and reads the answer back from another JSON file. Dorico waits while the script runs, as it would for a
modal dialog.

```lua
local ok, how, code = os.execute(command)   -- Lua 5.2: true|nil, "exit"|"signal", code
```

- Give each run an id that the dialog echoes in its answer, and treat an answer with another id, or none, as a
  cancel. Then a response file left from an earlier run can never be mistaken for this one's.
- Treat any failure as a cancel, and log why: no response file, unreadable JSON, a script that failed to start.
- An empty Lua table is ambiguous in JSON. The plug-in's encoder writes `{}` for it, so the dialog script
  must read `{}` as an empty list too.

### Windows: PowerShell and Windows Forms

```
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<dialog.ps1>" -Request "<req.json>" -Response "<resp.json>"
```

- Nothing to install: Windows PowerShell 5.1 and Windows Forms are on every Windows 10 and 11 machine.
- Startup takes about 6 seconds, mostly loading PowerShell and Windows Forms. Keep the script small.
- `-WindowStyle Hidden` stops a console window flashing up, and `TopMost` puts the form in front of Dorico.
- Begin the command with `powershell`, not a quoted path. `os.execute` goes through `cmd.exe`, which strips the
  first and last quotes from a line that starts with one.
- Write the response as UTF-8 **without** a byte-order mark: `[System.IO.File]::WriteAllText(path, text, (New-Object
  System.Text.UTF8Encoding $false))`.

PowerShell traps we fell into:

- Call `SetProcessDPIAware()` and scale your fixed sizes, or the dialog is drawn blurry on a high-DPI screen.
- Set `UseMnemonic = $false` on labels, or "P&F" shows as "PF".
- `ConvertFrom-Json` hands back a one-item list as a bare value, and Lua's `{}` as an empty object. Normalise
  every list.
- `-eq`, `-contains` and property lookups ignore case, while Lua doesn't. Use `-ceq` and `-ccontains` for names.
- Variable names ignore case too: `$button` *is* the parameter `$Button`, and assigning to it converts the value
  to the parameter's type.
- `$null` passed to a .NET `string` parameter arrives as `""`. Use `[NullString]::Value`.
- With `-File`, a comma list arrives as one string (`"a,b"`). Split it yourself.
- A `DataGridView` check box counts only when its cell is left. Commit on `CurrentCellDirtyStateChanged`. The grid
  also keeps Enter for itself, so give OK the first focus if Enter should press it.
- Cap the results window's height and let long text scroll, or a long report pushes OK off the screen.

### Mac: JavaScript for Automation (written, not yet run on a Mac)

```
/usr/bin/osascript -l JavaScript '<dialog.js>' '<req.json>' '<resp.json>' 2>'<error log>'
```

JavaScript for Automation (JXA) can use AppKit directly through its Objective-C bridge, so the dialog is a real
Cocoa window with nothing to install, the same on Apple silicon and Intel. Quote every path with single quotes,
escaping any `'` inside as `'\''`. Points that matter in JXA:

- A method with no arguments is reached as a property (`window.center`, `alert.runModal`), not called.
- `ObjC.registerSubclass` makes the target object for buttons and the flipped view a top-down layout needs. Keep
  a reference to the target, since controls hold their target weakly.
- `NSPopUpButton.addItemWithTitle` silently drops an item whose title repeats. Add `NSMenuItem`s to its menu instead,
  and turn off `autoenablesItems` or the items show grey.
- Run the window with `runModalForWindow` and end it with `stopModalWithCode`.
- The script is a process in the background. Set the activation policy to accessory, give the window the floating
  level so it stays above Dorico, and call `orderFrontRegardless`. An `NSAlert`'s window hides when its app isn't
  active, so call `setHidesOnDeactivate(false)` on it.
- Text fields take Cmd-C, Cmd-V and Cmd-A through the main menu, and a script has none: give it an Edit menu.
- Read and write files through `NSString` with UTF-8.
- If `os.execute` returns before the user could have answered, the plug-in polls for the response file instead of
  taking the missing file as a cancel. We don't yet know whether Dorico waits for `osascript` on a Mac.
- Keep the non-AppKit parts (reading the request, building the response) in plain functions, and test them under
  Node.

## 9. Testing from outside Dorico

### The Remote Control API

With Remote Control enabled in Dorico, a WebSocket at `ws://127.0.0.1:4560` takes JSON messages:

- `connect` with a client name and `handshakeVersion: "1.0"`. The first time, Dorico replies with a session token:
  answer with `acceptsessiontoken`, and keep the token for next time. Then the reply's `code` is `kConnected`.
- `command` with a command string, `getstatus`, `getcommands`, `getflows`, `getoptions` and `setoptions`.
- **Status messages are partial.** Each is a delta: merge it into what you have. Dorico pushes them unasked, so read
  any that are already waiting before trusting the state.
- Some commands are refused from the Remote API that work from Lua (a player rename came back `kError`).

`tools/dorico/dws.py` is a client using only the Python standard library.

### Running a script and getting results back

- `Script.RunScript?ScriptPath=<path>&ShowConsole=false` runs a Lua script. The reply comes back at once, without
  waiting for the script, and scripts queue up behind each other.
- So the script reports through a file: it writes `result.json` (checks, facts, any error), and the driver waits for
  it. Give each run an id, and only accept a result carrying it.
- **Run through a launcher.** A script that Dorico reaches late, after the driver gave up waiting, must not read the
  next run's arguments. The driver writes a small Lua file for each run that sets a global naming that run's
  arguments file, runs the real script, and clears the global (`tools/dorico/run_lua.py`).
- Check syntax with `luac -p` before sending anything, since Dorico skips a broken script silently.

### Never touch the user's work

- Run tests only on scratch copies: copy the project to a scratch folder, open the copy with
  `File.Open?File=<path>`, and close it with `File.CloseProject?OpenScoreID=<id>&Save=false`.
- **Confirm the active project is the copy** before changing anything, inside the script: compare the text export's
  `Path` with the copy's path. If they differ, refuse.
- **Wait for a newly opened project to settle.** Its id shows in the status before Dorico has finished with it, and
  a burst of status messages follows for a second or more. A script run straight away on a 23-flow project found
  `File.Export.Text` writing nothing. The runner waits until Dorico has sent nothing for two seconds.
- Dorico can ignore a close that arrives while it's still finishing a script, so check the copy's window is gone and
  try again.
- Opening a second project asks "Activate Project for Playback". Escape answers it. A project from an older version
  asks about upgrading. Save your test inputs with the current version.

### Driving dialogs

- **UI Automation waits on a busy Dorico.** While Dorico is blocked in `os.execute`, searching the desktop through UI
  Automation can take minutes, and taking a screenshot of every window hangs. Find windows with Win32 instead
  (`FindWindow`, `EnumWindows`, `GetWindowText`), which reads other programs' titles without asking them.
- UI Automation sees Windows Forms controls as bare panes. Press buttons with `BM_CLICK` on their window handle, and
  click grid cells with posted mouse messages.

### Unit tests without Dorico

Keep Dorico calls in a thin layer and everything else in pure Lua modules, then test those with stock Lua 5.2. The
plug-in has a test that fails if a pure module mentions `DoApp` or `DoCore`. Code in the Dorico layer can still be
unit-tested by replacing the modules it requires in `package.loaded` with stubs.

## 10. Gotchas, in one list

- One Lua state for the session: clear your modules, guard `package.path`, clear your globals.
- Syntax errors are skipped silently. Runtime errors end the script. Catch and report both yourself.
- `stream.events` throws on most real music. `stream:dump()` always works but has no properties.
- Every pitch is sounding, and nothing says how an instrument transposes.
- Players have no id and no `==`. Player ids aren't instrument ids.
- `flow.instruments[i].streams` is broken. `flow.instruments[i].id` owns `flow.voiceStreams[i]`.
- A colour set in the Properties panel, or by any command, reads as `""`. `getPropertyNames()` still lists it.
- `MIDIPitchWithSpelling.fromString` can crash Dorico on bad input.
- `EventEdit.Select` needs the event's block id, from `stream.blockInstances`. The dump prints an instance id, and a
  wrong block id selects nothing, silently.
- `kEventHide` hides neither texts nor rests. Naturals hide only by command.
- A system break needs a barline. A new flow has none.
- Layout options can be set, never read.
- The Remote API's `setoptions` with `flowIDs` changes flow 0.
- A plug-in can't delete a player.
- `Project.Flow.New` adds every player to the new flow.
- A run's edits are one undo step, object-model edits included. Only the first `Edit.Undo` in a run is safe.
- Command values escape `\`, `&` and `,`. Check every value and id before sending.
- `os.execute` freezes Dorico until it returns.
- PowerShell: case-insensitive comparisons and variable names, `$null` to `""`, one-item lists unwrapped, labels
  eating `&`.
- UI Automation can hang on a busy Dorico. Use Win32 to find windows.
- A project that has just opened isn't ready yet. Wait for the status messages to stop.
- The text export may have no flow numbers and no hidden texts.

## 11. Where to look in this repository

| Topic | Files |
| ----- | ----- |
| Entry file and module loading | `plugin/Handbells Used Chart.lua` |
| One run, start to finish | `plugin/Handbells Used Chart/hbuc/main.lua` |
| Reading notes, the paste route, the single undo | `hbuc/dorico/readscore.lua`, `hbuc/dump.lua`, `hbuc/eventtext.lua`, `hbuc/reading.lua` |
| The text export | `hbuc/dorico/doc.lua` (`exportText`), `hbuc/textexport.lua` |
| Drawing into the score | `hbuc/dorico/writechart.lua`, `hbuc/chartlayout.lua` |
| Player ids | `hbuc/dorico/doc.lua` (`playerIds`) |
| Command strings | `hbuc/commands.lua` |
| The dialogs | `hbuc/dorico/dialog.lua`, `dialog/windows.ps1`, `dialog/mac.js` |
| Probes | `spike/*.lua` |
| Running scripts in Dorico from Python | `tools/dorico/run_lua.py`, `tools/dorico/dws.py`, `spike/lib/probe.lua` |
| In-Dorico tests | `tests/dorico/` |

Paths under `hbuc/` and `dialog/` are inside `plugin/Handbells Used Chart/`.
