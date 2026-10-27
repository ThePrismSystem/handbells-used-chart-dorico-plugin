-- Give the chart flow no final barline and no visible rests, leaving the music flow alone.
-- Runs on a scratch copy already prepared by spike/01_pitch.lua (chart flow first, one Handbells chart player).
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua;" .. here .. "../spike/lib/?.lua"
for name in pairs(package.loaded) do -- Dorico keeps one Lua state between runs: reload our modules
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")
local layoutopts = require("layoutopts")
local events = require("events")

local RL = function(n, d) if d then return DoCore.RhythmicLength(n, d) end return DoCore.RhythmicLength(n) end

probe.run("05_meter", function(p)
  local app = DoApp.DoApp()
  local score = app.currentScore
  local ctx = DoCore.PropertyContext()
  local chart = score.flows[1]
  p:check("chart flow is first", #chart.players == 1, #chart.players)
  -- only the chart flow's option is set; the music flow's own barline settings are never touched
  -- (spike/run_recipe.py reads both flows' options back through the Remote API)
  app:doCommand(layoutopts.flowNotationCommand(score.openScoreID, chart.id, { ["barlineOptions.finalBarlineType"] = "kNone" }))

  local treble, bass = chart.voiceStreams[1], chart.voiceStreams[2]
  -- A: explicit rest over the bass gap, hidden
  local okR, rest = pcall(function() return bass:createRest(RL(1), RL(5)) end)
  p:check("createRest in the bass gap", okR, tostring(rest))
  if okR then
    local okH = rest.propertyTable:set("kEventHide", DoCore.Variant.createString("true"), ctx)
    p:fact("restHide", tostring(okH) .. " -> " .. tostring(rest.propertyTable:get("kEventHide", ctx)))
  end
  local bassEvents = {}
  for _, e in ipairs(bass.events) do bassEvents[#bassEvents + 1] = tostring(e) end
  p:fact("bassEvents", bassEvents)

  -- B: Edit.RemoveRests on the treble voice's selection
  local block = tonumber(treble:dump():match("Start block id: (%d+)")) - 1000
  local last
  for _, e in ipairs(treble.events) do
    local ev = events.parse(tostring(e))
    if ev.kind == "note" then last = e end
  end
  app:doCommand("Edit.SelectNone")
  app:doCommand("EventEdit.Select?FlowID=" .. chart.id .. "&EventID=" .. last.id .. "&EventBlockID=" .. block)
  app:doCommand("Edit.SelectAtEndOfFlow")
  app:doCommand("Edit.RemoveRests")
  app:doCommand("Edit.SelectNone")
  local trebleEvents = {}
  for _, e in ipairs(chart.voiceStreams[1].events) do trebleEvents[#trebleEvents + 1] = tostring(e):gsub("\n.*", "") end
  p:fact("trebleEventsAfterRemoveRests", trebleEvents)
end)
