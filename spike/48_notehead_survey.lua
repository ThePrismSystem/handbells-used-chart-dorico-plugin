-- Which notehead sets survive a MusicXML export? On a scratch copy of the fixture: a new flow gets one note
-- (args.beats long, default a quarter) per set id in args.ids, in order, on the first player's first voice (set from Lua) and again on the second
-- player's first voice (set by Edit.SetNoteheadSetOverride, as Dorico's UI does). A second run (args.step =
-- "export") opens Dorico's MusicXML export dialog; spike/48_notehead_survey.py presses OK and reads the file.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../"
local mine = here .. "lib/?.lua;" .. repo .. "tests/dorico/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("48_notehead_survey", function(p)
  -- In a run of its own: a flow made in the same run as the export was exported as an empty <score-partwise/>.
  if p.args.step == "export" then
    DoApp.DoApp():doCommand("File.Export?FilterID=MusicXMLExportFilter")
    p:fact("exported", true)
    return
  end
  local cases = require("cases")
  local commands = require("hbuc.commands")
  local doc = require("hbuc.dorico.doc")
  local ctx = cases.context(p)
  local app, log = ctx.app, ctx.log
  local pctx = DoCore.PropertyContext()
  local ids = p.args.ids

  local existing = {}
  for _, f in ipairs(app.currentScore.flows) do existing[f.id] = true end
  doc.command(app, log, "Project.Flow.New")
  local flowId
  for _, f in ipairs(app.currentScore.flows) do
    if not existing[f.id] then flowId = f.id end
  end
  if not flowId then error("Project.Flow.New did not add a flow") end
  p:fact("flowNumber", doc.flowNumber(app.currentScore, flowId))

  -- the first voice of each of the first two players
  local voices, seen = {}, {}
  for _, o in ipairs(doc.voiceOwners(doc.flowById(app.currentScore, flowId))) do
    if not seen[o.key] then
      seen[o.key] = true
      voices[#voices + 1] = o.stream
    end
  end
  local byLua, byCommand = voices[1], voices[2]

  local luaSet, commandIds, firstId = {}, {}, nil
  local beats = p.args.beats or 1
  for i, id in ipairs(ids) do
    local pos, len = DoCore.RhythmicLength((i - 1) * beats), DoCore.RhythmicLength(beats)
    local a = byLua:createNote(pos, len, DoCore.MIDIPitchWithSpelling.fromString("C5"))
    firstId = firstId or a.id
    luaSet[#luaSet + 1] = tostring(a.propertyTable:set("kNoteheadSetOverride", DoCore.Variant.createString(id), pctx))
    local b = byCommand:createNote(pos, len, DoCore.MIDIPitchWithSpelling.fromString("C5"))
    commandIds[i] = b.id
  end
  for i, id in ipairs(ids) do
    doc.select(app, log, flowId, commandIds[i], doc.blockIdOf(byCommand, commandIds[i]))
    doc.command(app, log, commands.build("Edit.SetNoteheadSetOverride", { { "NoteheadSetEntityID", id } }))
  end
  -- A new flow has no time signature, and Dorico exported it as an empty <score-partwise/>.
  doc.select(app, log, flowId, firstId, doc.blockIdOf(byLua, firstId))
  doc.command(app, log, "NoteInput.CreateTimeSignature?Definition=4/4")
  doc.command(app, log, "Edit.SelectNone")
  p:fact("luaSet", luaSet)

  -- how each reads back from Lua, in order
  local function reads(stream)
    local out = {}
    for _, e in ipairs(stream.events) do
      if tostring(e):match("^kNoteEvent") then out[#out + 1] = tostring(e.propertyTable:get("kNoteheadSetOverride", pctx)) end
    end
    return out
  end
  p:fact("readByLua", reads(byLua))
  p:fact("readByCommand", reads(byCommand))

end)
