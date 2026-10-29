-- findchart.find on a scratch copy, optionally after renaming the first flow (the chart's) by command.
--   args.renameTo: a new title for flows[1] before looking
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../../"
local mine = here .. "lib/?.lua;" .. repo .. "spike/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
-- first, whatever came before: the plug-in's entry file (test_run.py's RealDialog) leaves its install on the
-- path, and an older install there would be loaded instead
if package.path:sub(1, #mine + 1) ~= mine .. ";" then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("case_find", function(p)
  -- required here, not above: a module that fails to load is then reported, and the copy closed
  local cases = require("cases")
  local commands = require("hbuc.commands")
  local findchart = require("hbuc.dorico.findchart")
  local ctx = cases.context(p)
  if p.args.renameTo then
    ctx.app:doCommand(commands.renameFlow(ctx.app.currentScore.flows[1].id, p.args.renameTo))
  end
  local found = findchart.find(ctx.app, ctx.log, ctx.folders.temp)
  p:fact("status", found.status)
  p:fact("reason", found.reason or "")
  p:fact("flowId", found.flowId or -1)
  local roles = {}
  for _, pl in ipairs(found.players or {}) do roles[#roles + 1] = pl.key .. "=" .. pl.role end
  p:fact("players", table.concat(roles, ","))
end)
