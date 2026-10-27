-- Set a full-score layout option from Lua (no Remote API), using the command string Dorico itself
-- logs for setoptions. args: value (the flowHeadingBehaviour to set), layoutId
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua;" .. here .. "../spike/lib/?.lua"
for name in pairs(package.loaded) do -- Dorico keeps one Lua state between runs: reload our modules
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")
local layoutopts = require("layoutopts")

probe.run("07_headings", function(p)
  local app = DoApp.DoApp()
  local score = app.currentScore
  local cmd = layoutopts.setCommand(score.openScoreID, p.args.layoutId, { flowHeadingBehaviour = p.args.value })
  p:fact("command", cmd)
  app:doCommand(cmd)
  p:check("command sent", true)
end)
