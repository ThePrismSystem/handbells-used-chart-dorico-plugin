-- Sets layout options on the open scratch copy, for spike/40_last_system.py.
--   args.options: {[path] = value}
--   args.layoutId: the layout to set them on (default 0, the fixture's full score)
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../"
local mine = here .. "lib/?.lua;" .. repo .. "tests/dorico/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("40_layout", function(p)
  local cases = require("cases")
  local commands = require("hbuc.commands")
  local doc = require("hbuc.dorico.doc")
  local ctx = cases.context(p)
  doc.command(ctx.app, ctx.log, commands.layoutOptions(ctx.app.currentScore.openScoreID, p.args.layoutId or 0,
    p.args.options))
end)
