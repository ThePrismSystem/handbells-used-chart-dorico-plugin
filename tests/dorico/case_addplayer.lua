-- Adds a player the way a user would (Dorico puts a new player into every flow, the chart's included) and records
-- its key. Scratch copy only.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../../"
local mine = here .. "lib/?.lua;" .. repo .. "spike/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("case_addplayer", function(p)
  -- required here, not above: a module that fails to load is then reported, and the copy closed
  local constants = require("hbuc.constants")
  local doc = require("hbuc.dorico.doc")
  local app = DoApp.DoApp()
  local key = doc.playerKey(app.currentScore:addPlayer(constants.TREBLE_INSTRUMENT, false, 1))
  p:fact("key", key)
  local inChart = false
  for _, k in ipairs(doc.flowKeys(app.currentScore.flows[1])) do
    if k == key then inChart = true end
  end
  p:fact("inChartFlow", inChart)
end)
