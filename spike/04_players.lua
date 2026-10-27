-- Add chart players, keep them out of the music flows, find their streams, remove one.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua;" .. here .. "../spike/lib/?.lua"
for name in pairs(package.loaded) do -- Dorico keeps one Lua state between runs: reload our modules
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")
local chartflow = require("chartflow")

-- progress trail outside the result file, in case a call takes the whole script down
local trail = io.open(os.getenv("TEMP") .. "/hbuc-run/progress.txt", "w")
local function mark(...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
  trail:write(table.concat(t, "\t"), "\n"); trail:flush()
end

local function describe(v)
  if type(v) == "table" then
    local items = {}
    for k, x in pairs(v) do items[#items + 1] = tostring(k) .. "=" .. tostring(x) end
    return "table{" .. table.concat(items, ", ") .. "}"
  end
  return type(v) .. ":" .. tostring(v)
end

-- Players have no __eq and no id; their (first) instrument's id is unique and stable.
local function playerKey(pl)
  return pl.instruments[1].id
end

local function flowById(score, id)
  for _, f in ipairs(score.flows) do if f.id == id then return f end end
end

probe.run("04_players", function(p)
  local app = DoApp.DoApp()
  mark("create chart flow")
  local chart = chartflow.create(app, "Handbells Used Chart")
  local chartId = chart.id
  p:fact("chartFlowId", chartId)
  local nPlayers = #app.currentScore.players

  mark("addPlayer handbells")
  local okH, handbells = pcall(function()
    return app.currentScore:addPlayer("instrument.pitchedpercussion.handbells", false, 1)
  end)
  p:fact("addPlayerReturn", (okH and "" or "ERR ") .. describe(handbells))
  mark("addPlayer returned", okH, describe(handbells))
  p:check("score:addPlayer(handbells) adds one player", okH and #app.currentScore.players == nPlayers + 1,
    #app.currentScore.players)
  if not okH then return end
  local hb = app.currentScore.players[#app.currentScore.players]
  p:fact("newPlayerToString", tostring(hb))
  p:fact("newPlayerKey", playerKey(hb))
  p:check("addPlayer returns the new player", playerKey(handbells) == playerKey(hb))

  -- where did the new player land?
  local membership = {}
  for _, f in ipairs(app.currentScore.flows) do
    local inFlow = false
    for _, pl in ipairs(f.players) do if playerKey(pl) == playerKey(hb) then inFlow = true end end
    membership[#membership + 1] = f.id .. ":" .. tostring(inFlow) .. "(" .. #f.players .. " players)"
  end
  p:fact("newPlayerFlowsAfterAdd", membership)

  mark("wire into chart flow only")
  for _, f in ipairs(app.currentScore.flows) do
    if f.id == chartId then
      if #f.players == 0 then f:addPlayer(hb) end
    else
      local n = #f.players
      pcall(function() f:removePlayer(hb) end)
      p:fact("musicFlow" .. f.id .. "PlayersAfterRemove", #flowById(app.currentScore, f.id).players .. " (was " .. n .. ")")
    end
  end
  chart = flowById(app.currentScore, chartId)
  p:check("chart flow has the chart player", #chart.players == 1, #chart.players)
  p:check("chart flow has 2 stave streams", #chart.staveStreams == 2, #chart.staveStreams)
  p:check("chart flow has a voice stream", #chart.voiceStreams >= 1, #chart.voiceStreams)
  local vs = {}
  for i, s in ipairs(chart.voiceStreams) do vs[i] = tostring(s) end
  p:fact("chartVoiceStreams", vs)
  local music = flowById(app.currentScore, 0)
  p:check("music flow still has exactly its 3 players", #music.players == 3, #music.players)

  mark("addPlayer glockenspiel")
  local okG, glock = pcall(function()
    return app.currentScore:addPlayer("instrument.pitchedpercussion.glockenspiel", false, 1)
  end)
  p:fact("addGlockReturn", (okG and "" or "ERR ") .. describe(glock))
  if okG then
    local gp = app.currentScore.players[#app.currentScore.players]
    for _, f in ipairs(app.currentScore.flows) do
      if f.id == chartId then f:addPlayer(gp) else pcall(function() f:removePlayer(gp) end) end
    end
    chart = flowById(app.currentScore, chartId)
    p:check("treble-only player adds 1 stave", #chart.staveStreams == 3, #chart.staveStreams)
  end

  mark("part layouts")
  local layouts = {}
  for _, l in ipairs(app.currentScore.layouts) do layouts[#layouts + 1] = tostring(l) end
  p:fact("layoutsAfterAdd", layouts)
  -- keep the chart flow out of part layouts so parts do not print a Tacet page for it
  local removedFrom = {}
  for _, l in ipairs(app.currentScore.layouts) do
    if l.id ~= 0 then
      local ok = pcall(function() l:removeFlow(chart) end)
      removedFrom[#removedFrom + 1] = l.id .. ":" .. tostring(ok) .. " -> " .. tostring(l)
    end
  end
  p:fact("removeFlowFromParts", removedFrom)
  mark("done")
end)
trail:close()
