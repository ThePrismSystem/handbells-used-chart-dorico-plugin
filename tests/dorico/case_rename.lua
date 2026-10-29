-- Renames the first player on a scratch copy, as the user would before a run. In a script run because the Remote
-- API refuses renames (kError).
--   args.name: the new name
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

probe.run("case_rename", function(p)
  -- required here, not above: a module that fails to load is then reported, and the copy closed
  local cases = require("cases")
  local commands = require("hbuc.commands")
  local doc = require("hbuc.dorico.doc")
  local ctx = cases.context(p)
  local app = ctx.app
  local key = doc.playerKey(app.currentScore.players[1])
  local ids = doc.playerIds(app, ctx.log)
  doc.command(app, ctx.log, commands.renamePlayerName(ids[key], p.args.name))
  local name = tostring(doc.playerByKey(app.currentScore, key))
  p:fact("name", name)
  p:check("renamed exactly", name == p.args.name, name)
end)
