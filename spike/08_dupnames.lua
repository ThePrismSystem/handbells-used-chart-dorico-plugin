-- Can the text-export stream map tell apart two instruments of the same kind whose names were never
-- customised (two plain "Handbells")? Run on a fixture copy.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua;" .. here .. "../spike/lib/?.lua"
for name in pairs(package.loaded) do -- Dorico keeps one Lua state between runs: reload our modules
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")
local streammap = require("streammap")

probe.run("08_dupnames", function(p)
  local app = DoApp.DoApp()
  local score = app.currentScore
  local music = score.flows[1]
  local before = {}
  for _, s in ipairs(music.voiceStreams) do before[s.id] = true end
  score:addPlayer("instrument.pitchedpercussion.handbells", false, 1)
  score:addPlayer("instrument.pitchedpercussion.handbells", false, 1)
  music = app.currentScore.flows[1]
  local fresh = {}
  for _, s in ipairs(music.voiceStreams) do
    if not before[s.id] then fresh[#fresh + 1] = s end
  end
  p:fact("newVoiceStreams", #fresh)
  local names = {}
  for i, pl in ipairs(app.currentScore.players) do names[i] = tostring(pl) end
  p:fact("playerNames", table.concat(names, ", "))
  local owners = streammap.owners(app, music)
  local byName = {}
  for _, s in ipairs(fresh) do
    local owner = owners[s.id] or "?"
    byName[owner] = (byName[owner] or 0) + 1
  end
  local distinct = {}
  for name, n in pairs(byName) do distinct[#distinct + 1] = name .. " x" .. n end
  table.sort(distinct)
  p:fact("newStreamOwners", table.concat(distinct, ", "))
  local count = 0
  for _ in pairs(byName) do count = count + 1 end
  p:check("the two new players' streams map to two different instrument names", count == 2, table.concat(distinct, ", "))
  p:check("no stream-map markers left", streammap.leftoverMarkers(app.currentScore.flows[1]) == 0)
end)
