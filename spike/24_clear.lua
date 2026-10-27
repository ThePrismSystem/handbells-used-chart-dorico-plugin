-- On a project where spike/11_chart_recipe.lua has drawn a chart (chart flow first), does
-- deleteEventsInRange on every stream of the chart flow clear its notes, texts, hidden time signatures and
-- system breaks, leaving the flow and its players for an update to reuse? Scratch copy only.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua"
for name in pairs(package.loaded) do
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

local RL = function(n) return DoCore.RhythmicLength(n) end

local function kinds(s)
  local ok, d = pcall(function() return s:dump() end)
  local seen = {}
  if ok then for k in d:gmatch(": (k%a+) %(id:") do seen[k] = (seen[k] or 0) + 1 end end
  local parts = {}
  for k, n in pairs(seen) do parts[#parts + 1] = k .. "=" .. n end
  table.sort(parts)
  return table.concat(parts, ",")
end

local function flowById(app, id)
  for _, f in ipairs(app.currentScore.flows) do if f.id == id then return f end end
end

probe.run("24_clear", function(p)
  local app = DoApp.DoApp()
  local chart = app.currentScore.flows[1]
  local chartId, players = chart.id, #chart.players
  p:fact("openScoreID", app.currentScore.openScoreID)
  local before = {}
  for _, s in ipairs(chart.allStreams) do before[#before + 1] = s.id .. "(" .. tostring(s.type) .. "):" .. kinds(s) end
  p:fact("before", before)
  for _, s in ipairs(chart.allStreams) do
    local ok, err = pcall(function() s:deleteEventsInRange(RL(0), RL(1000)) end)
    if not ok then p:fact("deleteError" .. s.id, tostring(err):sub(1, 200)) end
  end
  chart = flowById(app, chartId)
  local after, left = {}, 0
  for _, s in ipairs(chart.allStreams) do
    local k = kinds(s)
    after[#after + 1] = s.id .. "(" .. tostring(s.type) .. "):" .. k
    if k ~= "" then left = left + 1 end
  end
  p:fact("after", after)
  p:check("every chart stream is empty", left == 0, left)
  p:check("chart flow keeps its players", #chart.players == players, #chart.players)
  p:check("chart flow still first", app.currentScore.flows[1].id == chartId)
end)
