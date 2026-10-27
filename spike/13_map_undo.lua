-- Does the stream map's temporary marker edit (object-model createText and delete) leave anything in
-- Dorico's undo history? If Edit.Undo afterwards brings markers back, reading before the dialog would leave
-- a trap for a user who cancels and then presses Undo.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua"
for name in pairs(package.loaded) do
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")
local streammap = require("streammap")

local function eventCount(flow)
  local n = 0
  for _, s in ipairs(flow.voiceStreams) do n = n + #s.events end
  return n
end

probe.run("13_map_undo", function(p)
  local app = DoApp.DoApp()
  local flow = app.currentScore.flows[1]
  local before = eventCount(flow)
  local owners = streammap.owners(app, flow)
  local n = 0
  for _ in pairs(owners) do n = n + 1 end
  p:check("map found every voice stream", n == #flow.voiceStreams, n)
  flow = app.currentScore.flows[1]
  p:check("events unchanged after the map", eventCount(flow) == before, eventCount(flow) .. " vs " .. before)
  for i = 1, 3 do
    app:doCommand("Edit.Undo")
    flow = app.currentScore.flows[1]
    p:fact("afterUndo" .. i, { events = eventCount(flow), markers = streammap.leftoverMarkers(flow) })
  end
  p:check("undo brings back no markers", streammap.leftoverMarkers(flow) == 0, streammap.leftoverMarkers(flow))
  p:check("undo changes no events", eventCount(flow) == before, eventCount(flow) .. " vs " .. before)
end)
