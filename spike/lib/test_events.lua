-- Unit tests for events.lua and streammap.lua's pure parts. Runs under stock Lua 5.2:
--   lua52 spike/lib/test_events.lua
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
for name in pairs(package.loaded) do
  if package.searchpath(name, here .. "?.lua") then package.loaded[name] = nil end
end
local mine = here .. "?.lua;" .. here .. "../../fixtures/?.lua"
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local events = require("events")
local streammap = require("streammap")

local failures = {}
local function eq(label, got, want)
  if got ~= want then failures[#failures + 1] = label .. ": got " .. tostring(got) .. ", want " .. tostring(want) end
end

-- events.parse ---------------------------------------------------------------------------
local n = events.parse("kNoteEvent (id:195) at 4, duration 1  G#5 (ends 5)")
eq("note kind", n.kind, "note")
eq("note id", n.id, 195)
eq("note pos", n.pos, 4)
eq("note spelling", n.spelling, "G#5")
eq("note name", n.name, "G#")
eq("note octave", n.octave, 5)

local f = events.parse("kNoteEvent (id:981) at 13/2 (6.5), duration 1/2 (0.5)  Bb4 (ends 7)")
eq("fraction pos", f.pos, 6.5)
eq("flat name", f.name, "Bb")

local g = events.parse("kGraceNoteEvent (id:200) at 8  secondary pos -1/2 (-0.5), notated duration: 1/2 (0.5), B6 ")
eq("grace kind", g.kind, "grace")
eq("grace pos", g.pos, 8)
eq("grace spelling", g.spelling, "B6")

local third = events.parse("kNoteEvent (id:982) at 1/3 (0.333333), duration 1/3 (0.333333)  Fx4 (ends 2/3)")
eq("an exact fraction, not the rounded decimal", third.pos, 1 / 3)
eq("double sharp spelling", third.spelling, "Fx4")
eq("double sharp name", third.name, "Fx")

local low = events.parse("kNoteEvent (id:228) at 13, duration 1  B-1 (ends 14)")
eq("negative octave", low.octave, -1)

local r = events.parse("kRestEvent (id:216) at 0, duration 1 ")
eq("rest kind", r.kind, "rest")
eq("rest has no spelling", r.spelling, nil)

local t = events.parse("kTextEvent (id:317) at 0 : HBUCMARK10\n (paragraph.defaulttext)")
eq("text kind", t.kind, "text")
eq("text body", t.text, "HBUCMARK10")

eq("unknown kind", events.parse("kClefEvent (id:185) at 0 \nClef entity ID").kind, "other")

-- streammap.parseExport ------------------------------------------------------------------
local csv = table.concat({
  '"Path","ID","FlowNumber","FlowName","Instrument","Page","Bar","Type","Text","Hidden"',
  '"","","","","","1","","Text Frame","Handbells Chart Fixture","N"',
  '"","0-10-317","1","Fixture","Handbells (A)","1","1","Staff-attached text (Default Text)","HBUCMAP10","N"',
  '"","0-13-319","1","Fixture","Handbells, ""B""","1","1","Staff-attached text (Default Text)","HBUCMAP13","N"',
  '"","0-17-322","1","Fixture","Organ","1","1","Staff-attached text (Default Text)","user text","N"',
}, "\r\n")
local owners = streammap.parseExport(csv, "HBUCMAP")
local wrapped = csv:gsub('"Fixture","Handbells %(A%)"', '"Fix\nture","Handbells (A)"')
eq("a quoted newline does not split a row", streammap.parseExport(wrapped, "HBUCMAP")[10], "Handbells (A)")
eq("owner of 10", owners[10], "Handbells (A)")
eq("quoted owner of 13", owners[13], 'Handbells, "B"')
eq("non-marker text ignored", owners[17], nil)

-- layoutopts.setCommand: must match what Dorico logs for the Remote API's setoptions ------
local layoutopts = require("layoutopts")
eq("set command", layoutopts.setCommand(11, 0, { flowHeadingBehaviour = "kNoFlowHeadings" }),
  'Project.Layout.SetOptions?Dictionary=list: {string: "flowHeadingBehaviour"}\\, {string: "kNoFlowHeadings"}&OpenScoreID=11&LayoutIDArray=0')
eq("two options, sorted", layoutopts.setCommand(0, 2, { b = "y", a = "x" }),
  'Project.Layout.SetOptions?Dictionary=list: {string: "a"}\\, {string: "x"}\\, {string: "b"}\\, {string: "y"}&OpenScoreID=0&LayoutIDArray=2')

eq("commas inside a value are escaped", layoutopts.setCommand(13, 0, { ["staffLabelLayoutOptions.playersToShowPlayerName"] = "3,4" }),
  'Project.Layout.SetOptions?Dictionary=list: {string: "staffLabelLayoutOptions.playersToShowPlayerName"}\\, {string: "3\\,4"}&OpenScoreID=13&LayoutIDArray=0')

eq("flow notation command", layoutopts.flowNotationCommand(15, 1, { ["barlineOptions.finalBarlineType"] = "kNone" }),
  'Project.Flow.SetNotationOptions?Dictionary=list: {string: "barlineOptions.finalBarlineType"}\\, {string: "kNone"}&OpenScoreID=15&FlowIDArray=1')

-- streammap.owners cleans up its markers on every path -------------------------------------
do
  local savedDoCore = rawget(_G, "DoCore")
  DoCore = { RhythmicLength = function(n) return n end }
  local function fakeStream(id, failCreate)
    local s = { id = id, events = {}, deleted = 0 }
    function s:createText(_, _, text)
      if failCreate then error("createText failed") end
      local e = setmetatable({ text = text }, { __tostring = function(t) return "kTextEvent (id:1) at 0 : " .. t.text end })
      self.events[#self.events + 1] = e
      return e
    end
    function s:delete(e)
      for i, x in ipairs(self.events) do
        if x == e then table.remove(self.events, i); self.deleted = self.deleted + 1; return true end
      end
      return false
    end
    return s
  end
  local first, second = fakeStream(10), fakeStream(11, true)
  local app = { doCommand = function() error("export should not run after a failed marker") end }
  local ok = pcall(streammap.owners, app, { voiceStreams = { first, second } })
  eq("owners fails when a marker cannot be created", ok, false)
  eq("the marker already made is deleted", first.deleted, 1)
  eq("no markers left behind", streammap.leftoverMarkers({ voiceStreams = { first, second } }), 0)
  local stale = fakeStream(12)
  stale:createText(0, 1, streammap.PREFIX .. "12")
  eq("leftover markers are counted", streammap.leftoverMarkers({ voiceStreams = { stale } }), 1)
  DoCore = savedDoCore
end

-- fixtureindex.add: two notes with one key would take each other's heads ----------------------
local fixtureindex = require("fixtureindex")
local index = {}
fixtureindex.add(index, "Handbells (A)|1|0|C5|n", { stream = 1 })
eq("a key is added", index["Handbells (A)|1|0|C5|n"].stream, 1)
eq("a second note with the same key is refused",
  pcall(fixtureindex.add, index, "Handbells (A)|1|0|C5|n", { stream = 2 }), false)

-- headings: recover flowHeadingBehaviour from text exports -------------------------------
local headings = require("headings")
local function export(frames)
  local lines = { '"Path","ID","FlowNumber","FlowName","Instrument","Page","Bar","Type","Text","Hidden"' }
  for _, f in ipairs(frames) do
    lines[#lines + 1] = '"","","","","","' .. f[1] .. '","","Text Frame","' .. f[2] .. '","N"'
  end
  lines[#lines + 1] = '"","","1","Chart","Global","","-1","Flow Info (Title)","Chart","N"'
  return table.concat(lines, "\r\n")
end
local always = export({ { 1, "Song" }, { 1, "1. Handbells Used Chart" }, { 2, "2. Song" } })
local afterFirst = export({ { 1, "Song" }, { 2, "2. Song" } })
local none = export({ { 1, "Song" } })
eq("text frame rows ignore non-frame rows", #headings.textFrameRows(always), 3)
eq("detects always", headings.decide(always, none, afterFirst), "kAlwaysInsertHeadings")
eq("detects after first flow", headings.decide(afterFirst, none, afterFirst), "kAddHeadingsAfterFirstFlow")
eq("detects none", headings.decide(none, none, afterFirst), "kNoFlowHeadings")
eq("row order does not matter", headings.decide(export({ { 2, "2. Song" }, { 1, "Song" } }), none, afterFirst),
  "kAddHeadingsAfterFirstFlow")

-- probe.isExpectedScratch: is the active project the scratch copy the runner opened? ---------
local probeLib = require("probe")
eq("same path, different case and slashes", probeLib.isExpectedScratch({ path = "C:/Temp/hbuc-run/scratch.dorico" },
  "c:\\temp\\hbuc-run\\SCRATCH.dorico"), true)
eq("untitled import expected and found", probeLib.isExpectedScratch({ path = "" }, ""), true)
eq("untitled expected, a saved project found", probeLib.isExpectedScratch({ path = "" }, "C:/Users/me/Song.dorico"), false)
eq("scratch expected, an untitled project found", probeLib.isExpectedScratch({ path = "C:/Temp/hbuc-run/scratch.dorico" }, ""), false)
eq("scratch expected, the user's project found", probeLib.isExpectedScratch({ path = "C:/Temp/hbuc-run/scratch.dorico" },
  "C:/Users/me/Song.dorico"), false)

-- probe.run: the runner's launcher names the run's args (HBUC_RUN), and an error table keeps its traceback --------
do
  local dir = ((os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("\\", "/"):gsub("/+$", "")) .. "/"
  local argsPath = dir .. "hbuc-test-probe-args.json"
  local f = assert(io.open(argsPath, "wb"))
  f:write('{"runId":"r1"}')
  f:close()
  local saved = { probe = package.loaded.probe, rundir = package.loaded.rundir }
  HBUC_RUN = { dir = dir, args = argsPath }
  package.loaded.probe, package.loaded.rundir = nil, nil
  local okRun, result = pcall(function()
    return require("probe").run("t", function() error({ code = "boom" }) end)
  end)
  HBUC_RUN = nil
  package.loaded.probe, package.loaded.rundir = saved.probe, saved.rundir
  os.remove(argsPath)
  os.remove(dir .. "result.json")
  eq("probe.run returns", okRun, true)
  if okRun then
    eq("the launcher's args are read", result.runId, "r1")
    eq("an error table names itself", tostring(result.error):find("boom", 1, true) ~= nil, true)
    eq("and keeps its traceback", tostring(result.error):find("stack traceback", 1, true) ~= nil, true)
  end
end

if DoApp then
  local probe = require("probe")
  probe.run("test_events", function(p) p:check("all events assertions", #failures == 0, table.concat(failures, "; ")) end)
else
  if #failures > 0 then
    for _, msg in ipairs(failures) do print("FAIL " .. msg) end
    os.exit(1)
  end
  print("events ok")
end
