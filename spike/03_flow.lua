-- Create the chart flow, rename it, move it to the start, and leave the music players out of it.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua;" .. here .. "../spike/lib/?.lua"
for name in pairs(package.loaded) do -- Dorico keeps one Lua state between runs: reload our modules
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

local function flowIds(score)
  local ids, order = {}, {}
  for i, f in ipairs(score.flows) do ids[f.id] = true; order[i] = f.id end
  return ids, order
end

probe.run("03_flow", function(p)
  local app = DoApp.DoApp()
  local score = app.currentScore
  local before, beforeOrder = flowIds(score)
  p:fact("flowsBefore", beforeOrder)

  app:doCommand("Project.Flow.New")
  local after, afterOrder = flowIds(app.currentScore)
  p:fact("flowsAfterNew", afterOrder)
  local newId
  for id in pairs(after) do if not before[id] then newId = id end end
  if not p:check("Project.Flow.New adds one flow", newId ~= nil and #afterOrder == #beforeOrder + 1, table.concat(afterOrder, ",")) then
    return
  end
  p:fact("newFlowId", newId)

  app:doCommand("Project.Flow.Rename?FlowID=" .. newId .. "&Name=Handbells Used Chart")
  -- the flow name is not exposed on the Lua Flow; read it back from the text export's FlowName column
  local base = os.getenv("TEMP"):gsub("\\", "/") .. "/hbuc-run/flownames"
  os.remove(base .. ".csv")
  app:doCommand("File.Export.Text?File=" .. base .. ".txt&Show=false")
  local f = io.open(base .. ".csv", "rb")
  local csv = f and f:read("*a") or ""
  if f then f:close() end
  p:check("rename shows in the text export", csv:find('"Handbells Used Chart"', 1, true) ~= nil)

  local tried = {}
  local moved
  for _, encoding in ipairs({ tostring(newId), "[" .. newId .. "]", newId .. ",", "{" .. newId .. "}" }) do
    app:doCommand("Project.Flows.MoveToStart?FlowIDArray=" .. encoding)
    local _, order = flowIds(app.currentScore)
    tried[#tried + 1] = encoding .. " -> " .. table.concat(order, ",")
    if order[1] == newId then moved = encoding; break end
  end
  p:fact("moveAttempts", tried)
  p:fact("flowIdArrayEncoding", moved or false)
  p:check("Project.Flows.MoveToStart puts the chart flow first", moved ~= nil)

  local chart
  for _, fl in ipairs(app.currentScore.flows) do if fl.id == newId then chart = fl end end
  p:fact("playersInNewFlow", #chart.players)
  local removed = 0
  for _, pl in ipairs(chart.players) do
    chart:removePlayer(pl)
    removed = removed + 1
  end
  local remaining = 0
  for _, fl in ipairs(app.currentScore.flows) do if fl.id == newId then remaining = #fl.players end end
  p:fact("removedPlayers", removed)
  p:check("flow:removePlayer leaves the chart flow empty", remaining == 0, remaining)

  -- music flows still have their players
  for _, fl in ipairs(app.currentScore.flows) do
    if fl.id ~= newId then p:check("music flow " .. fl.id .. " keeps its players", #fl.players == 3, #fl.players) end
  end
end)
