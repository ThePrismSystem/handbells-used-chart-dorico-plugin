-- Create the chart flow the way spike/03_flow.lua proved: new flow, rename, move to the start, no players.
local chartflow = {}

-- {[flowId] = true} for the score's flows
function chartflow.flowIds(score)
  local ids = {}
  for _, f in ipairs(score.flows) do ids[f.id] = true end
  return ids
end

local function findFlow(score, id)
  for _, f in ipairs(score.flows) do
    if f.id == id then return f end
  end
end

-- Returns the new flow (now score.flows[1]); errors if any step does not take effect.
function chartflow.create(app, name)
  local before = chartflow.flowIds(app.currentScore)
  app:doCommand("Project.Flow.New")
  local newId
  for id in pairs(chartflow.flowIds(app.currentScore)) do
    if not before[id] then newId = id end
  end
  if not newId then error("Project.Flow.New did not add a flow") end
  app:doCommand("Project.Flow.Rename?FlowID=" .. newId .. "&Name=" .. name)
  app:doCommand("Project.Flows.MoveToStart?FlowIDArray=" .. newId)
  local flow = findFlow(app.currentScore, newId)
  if app.currentScore.flows[1].id ~= newId then error("Project.Flows.MoveToStart did not move flow " .. newId) end
  for _, player in ipairs(flow.players) do flow:removePlayer(player) end
  flow = findFlow(app.currentScore, newId)
  if #flow.players ~= 0 then error("chart flow still has " .. #flow.players .. " players") end
  return flow
end

-- Players have no __eq and no id; their first instrument's id is unique.
function chartflow.playerKey(player)
  return player.instruments[1].id
end

-- Add a player for instrumentEntityID that belongs to chartFlow only. Returns the player.
function chartflow.addChartPlayer(app, chartFlow, instrumentEntityID)
  local chartId = chartFlow.id
  local player = app.currentScore:addPlayer(instrumentEntityID, false, 1)
  local key = chartflow.playerKey(player)
  for _, f in ipairs(app.currentScore.flows) do
    local has = false
    for _, pl in ipairs(f.players) do if chartflow.playerKey(pl) == key then has = true end end
    if f.id == chartId and not has then f:addPlayer(player) end
    if f.id ~= chartId and has then f:removePlayer(player) end
  end
  return player
end

return chartflow
