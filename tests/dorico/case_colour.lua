-- Colours the first note of the fixture's first voice red by command, as the Properties panel does, before a read.
-- Lua can't read a colour set that way, but the saved copy the read uses has it.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../../"
local mine = here .. "lib/?.lua;" .. repo .. "spike/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("case_colour", function(p)
  -- required here, not above: a module that fails to load is then reported, and the copy closed
  local cases = require("cases")
  local commands = require("hbuc.commands")
  local dump = require("hbuc.dump")
  local doc = require("hbuc.dorico.doc")
  local ctx = cases.context(p)
  local app = ctx.app
  local flow = app.currentScore.flows[1]
  local stream = flow.voiceStreams[1]
  local note = dump.notes(doc.dumpOf(stream))[1]
  p:fact("note", note.spelling)
  doc.select(app, ctx.log, flow.id, note.id, doc.blockIdOf(stream, note.id))
  doc.command(app, ctx.log, commands.build("UI.InvokePropertyChangeValue",
    { { "Type", "kEventColour" }, { "Value", "#ffff0000" } }))
  doc.command(app, ctx.log, "Edit.SelectNone")
end)
