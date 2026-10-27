-- Is flow.instruments one entry per voice stream, in voiceStreams order, each carrying the owning
-- instrument's id? Compared against the text-export stream map on a score whose staves hold more than one
-- voice. The map's markers are removed again, so the copy ends unchanged.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua"
for name in pairs(package.loaded) do
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")
local streammap = require("streammap")

probe.run("14_flow_instruments", function(p)
  local app = DoApp.DoApp()
  local score = app.currentScore
  p:fact("openScoreID", score.openScoreID)
  local nameOfInstrument = {}
  for _, pl in ipairs(score.players) do
    for _, ins in ipairs(pl.instruments) do nameOfInstrument[ins.id] = tostring(pl) end
  end
  local flows = {}
  for fi, flow in ipairs(score.flows) do
    if fi > 2 then break end
    local owners = streammap.owners(app, flow)
    flow = score.flows[fi]
    local fis = flow.instruments
    local rows, agree = {}, true
    for i, s in ipairs(flow.voiceStreams) do
      local f = fis[i]
      local fid = f and f.id
      rows[#rows + 1] = { stream = s.id, events = #s.events, exportOwner = owners[s.id],
        fiId = fid, fiPlayer = fid and nameOfInstrument[fid] }
    end
    flows[#flows + 1] = { flow = flow.id, voices = #flow.voiceStreams, flowInstruments = #fis,
      staves = #flow.staveStreams, rows = rows }
  end
  p:fact("flows", flows)
end)
