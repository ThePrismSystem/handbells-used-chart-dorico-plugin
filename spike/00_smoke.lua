local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua;" .. here .. "../spike/lib/?.lua"
for name in pairs(package.loaded) do -- Dorico keeps one Lua state between runs: reload our modules
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("smoke", function(p)
  local app = DoApp.DoApp()
  p:check("version 6", app.versionString:sub(1, 2) == "6.", app.versionString)
  local score = app.currentScore
  p:check("has score", score ~= nil)
  p:fact("version", app.versionString)
  p:fact("title", score and score.title)
  p:fact("flows", score and #score.flows)
  -- Dorico keeps one Lua state between runs, so this global survives from the previous run.
  p:fact("previousRunMarker", rawget(_G, "HBUC_SMOKE_MARKER") or false)
  HBUC_SMOKE_MARKER = p.args.runId
end)
