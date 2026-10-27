-- Can a voice stream's owning instrument or player be read without editing the score? Tries likely property
-- names on streams, flow instruments, players and instruments, and keeps the start of each voice stream's
-- dump. Read-only: changes nothing.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua"
for name in pairs(package.loaded) do
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

local function try(obj, key)
  local ok, v = pcall(function() return obj[key] end)
  if not ok then return "error: " .. tostring(v):sub(1, 80) end
  if v == nil then return nil end
  local okS, s = pcall(tostring, v)
  return okS and s:sub(1, 120) or ("<" .. type(v) .. ">")
end

local STREAM_KEYS = { "id", "instrument", "instrumentID", "instrumentId", "player", "playerID", "owner", "ownerID",
  "staffID", "staff", "voiceID", "voice", "name", "type", "index", "flowInstrument", "parentID", "parent" }
local FI_KEYS = { "id", "instrument", "instrumentID", "player", "streams", "voiceStreams", "staveStreams",
  "name", "staves", "voices" }

probe.run("12_owners", function(p)
  local app = DoApp.DoApp()
  local score = app.currentScore
  local flow = score.flows[1]
  local streams = {}
  for i, s in ipairs(flow.voiceStreams) do
    local entry = { index = i, keys = {} }
    for _, k in ipairs(STREAM_KEYS) do entry.keys[k] = try(s, k) end
    local okD, dump = pcall(function() return s:dump() end)
    entry.dumpHead = okD and dump:sub(1, 700) or ("dump error: " .. tostring(dump))
    streams[#streams + 1] = entry
  end
  p:fact("voiceStreams", streams)

  local fis = {}
  local okFi, list = pcall(function() return flow.instruments end)
  if okFi and list then
    for i, fi in ipairs(list) do
      local entry = { index = i, keys = {} }
      for _, k in ipairs(FI_KEYS) do entry.keys[k] = try(fi, k) end
      local okS, ss = pcall(function() return fi.streams end)
      entry.streamCount = okS and ss and #ss or -1
      fis[#fis + 1] = entry
    end
  end
  p:fact("flowInstruments", fis)

  local players = {}
  for i, pl in ipairs(score.players) do
    local ids = {}
    for _, ins in ipairs(pl.instruments) do ids[#ids + 1] = ins.id end
    players[#players + 1] = { index = i, name = tostring(pl), instrumentIds = ids,
      flowsKey = try(pl, "flows"), streams = try(pl, "streams"), voiceStreams = try(pl, "voiceStreams") }
  end
  p:fact("players", players)

  local ps = {}
  local okP, pstreams = pcall(function() return flow.playerStreams end)
  if okP and pstreams then
    for i, s in ipairs(pstreams) do
      local okD, dump = pcall(function() return s:dump() end)
      ps[#ps + 1] = { index = i, id = try(s, "id"), events = #s.events, dumpHead = okD and dump:sub(1, 400) or "" }
    end
  end
  p:fact("playerStreams", ps)
end)
