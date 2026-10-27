-- Dorico makes a part layout for every chart player. Which layouts hold only chart players, and does
-- Project.Layouts.Delete?LayoutIDArray=<id> remove one silently? Runs on the recipe's scratch copy, where
-- the chart flow is first and its players are the chart players.
--   args.delete: true to try deleting the first chart-player part layout
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua"
for name in pairs(package.loaded) do
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

local function layoutRows(score, chartKeys)
  local rows, onlyChart = {}, {}
  for _, l in ipairs(score.layouts) do
    local keys, chartOnly = {}, #l.players > 0
    for _, pl in ipairs(l.players) do
      local k = pl.instruments[1].id
      keys[#keys + 1] = k
      if not chartKeys[k] then chartOnly = false end
    end
    rows[#rows + 1] = l.id .. ": " .. tostring(l) .. " players " .. table.concat(keys, ",")
    if chartOnly and l.id ~= 0 then onlyChart[#onlyChart + 1] = l.id end
  end
  return rows, onlyChart
end

probe.run("25_part_layouts", function(p)
  local app = DoApp.DoApp()
  local score = app.currentScore
  local chartKeys = {}
  for _, pl in ipairs(score.flows[1].players) do chartKeys[pl.instruments[1].id] = true end
  local rows, onlyChart = layoutRows(score, chartKeys)
  p:fact("layoutsBefore", rows)
  p:fact("chartOnlyLayouts", onlyChart)
  if p.args.delete and onlyChart[1] then
    app:doCommand("Project.Layouts.Delete?LayoutIDArray=" .. onlyChart[1])
    local after = layoutRows(app.currentScore, chartKeys)
    p:fact("layoutsAfter", after)
    p:check("one layout fewer", #after == #rows - 1, #after .. " vs " .. #rows)
  end
end)
