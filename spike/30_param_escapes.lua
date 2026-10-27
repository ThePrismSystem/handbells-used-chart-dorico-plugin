-- Can a command parameter carry '&' or '='? Renames player key 0 (fixture: Handbells (A)) with several encodings,
-- reading the name back after each, and finally restores it with Name only. Scratch copy only.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua"
for name in pairs(package.loaded) do
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("30_param_escapes", function(p)
  local app = DoApp.DoApp()
  local function player0()
    for _, pl in ipairs(app.currentScore.players) do
      if pl.instruments[1].id == 0 then return pl end
    end
  end
  local original = tostring(player0())
  local tries = {}
  for _, value in ipairs({ "P=F", "a=b=c", "x\\&y=z\\\\w", "=start", "Handbells (P\\&F)" }) do
    app:doCommand("Project.Player.Rename?PlayerID=0&Name=" .. value)
    tries[#tries + 1] = value .. " -> [" .. tostring(player0()) .. "]"
  end
  app:doCommand("Project.Player.Rename?PlayerID=0&Name=" .. original)
  p:fact("tries", tries)
  p:fact("restored", tostring(player0()) == original)
end)
