-- Deletes one flow, named in the text export's FlowName column, as a user would (Dorico asks to confirm), to
-- compare a project's pages with and without a hand-made chart flow (spike/43_handmade.py).
--   args.name: the flow's name
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../"
local mine = here .. "lib/?.lua;" .. repo .. "tests/dorico/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("43_delete_flow", function(p)
  local cases = require("cases")
  local commands = require("hbuc.commands")
  local textexport = require("hbuc.textexport")
  local doc = require("hbuc.dorico.doc")
  local ctx = cases.context(p)
  local app = ctx.app
  local number
  for _, rec in ipairs(textexport.csvRecords(doc.exportText(app, ctx.log, ctx.folders.temp, "flow-names"))) do
    if rec.FlowName == p.args.name and rec.FlowNumber ~= "" then number = tonumber(rec.FlowNumber) end
  end
  if not number then error("no flow named " .. tostring(p.args.name)) end
  local id = app.currentScore.flows[number].id
  p:fact("deleting", number .. ": id " .. id)
  doc.command(app, ctx.log, commands.setMode("kSetupMode"))
  doc.command(app, ctx.log, commands.deleteFlow(id))
  doc.command(app, ctx.log, commands.setMode("kWriteMode"))
  p:check("the flow is gone", doc.flowById(app.currentScore, id) == nil)
  p:fact("flowCount", #app.currentScore.flows)
end)
