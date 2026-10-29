-- findchart.find then removechart.remove on a scratch copy. Dorico's Delete Flow and Delete Empty Players
-- dialogs are answered by the Python driver while this runs.
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

probe.run("case_remove", function(p)
  -- required here, not above: a module that fails to load is then reported, and the copy closed
  local cases = require("cases")
  local doc = require("hbuc.dorico.doc")
  local findchart = require("hbuc.dorico.findchart")
  local removechart = require("hbuc.dorico.removechart")
  local ctx = cases.context(p)
  local app = ctx.app
  local found = findchart.find(app, ctx.log, ctx.folders.temp)
  if not p:check("a chart to remove", found.status == "ok", found.status) then return end
  local out = removechart.remove(app, found, { log = ctx.log })
  p:fact("removed", out.removed)
  p:fact("flowCount", #app.currentScore.flows)
  local left = {}
  for _, k in ipairs(found.marker.chartPlayers) do
    if doc.playerByKey(app.currentScore, k) then left[#left + 1] = k end
  end
  p:fact("chartPlayersLeft", table.concat(left, ","))
  local layoutsLeft = 0
  for _, l in ipairs(doc.layouts(app.currentScore)) do
    local onlyChart = #l.keys > 0
    for _, k in ipairs(l.keys) do
      local isChart = false
      for _, c in ipairs(found.marker.chartPlayers) do if c == k then isChart = true end end
      if not isChart then onlyChart = false end
    end
    if onlyChart then layoutsLeft = layoutsLeft + 1 end
  end
  p:fact("chartLayoutsLeft", layoutsLeft)
end)
