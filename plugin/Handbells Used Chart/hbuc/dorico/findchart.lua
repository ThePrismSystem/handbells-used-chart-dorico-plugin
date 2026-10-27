-- Gathers what chartcheck needs to decide whether the project holds a chart this plug-in may change: every
-- marker text (from the dumps, which work on any stream), each flow's title (text export) and players.
local chartcheck = require("hbuc.chartcheck")
local dump = require("hbuc.dump")
local marker = require("hbuc.marker")
local textexport = require("hbuc.textexport")
local doc = require("hbuc.dorico.doc")

local findchart = {}

-- chartcheck's result; when it is "ok", also players = {{key, role}} in marker order, the role read from how
-- many voice streams the player has in the chart flow (a grand staff has two).
function findchart.find(app, log, tempDir)
  local score = app.currentScore
  local titles = textexport.flowTitles(doc.exportText(app, log, tempDir, "find-titles"))
  local info = { markers = {}, flowTitles = {}, allTitles = titles.all, flowPlayers = {}, flowNotes = {},
    playerNames = {} }
  for _, pl in ipairs(score.players) do info.playerNames[doc.playerKey(pl)] = tostring(pl) end
  for i, f in ipairs(score.flows) do
    info.flowTitles[f.id] = titles[i]
    info.flowPlayers[f.id] = doc.flowKeys(f)
    local notes = {}
    for _, o in ipairs(doc.voiceOwners(f)) do
      local parsed = doc.dumpOf(o.stream)
      notes[o.key] = (notes[o.key] or 0) + #dump.notes(parsed)
      for _, ev in ipairs(parsed.events) do
        if ev.kind == "text" and marker.isMarker(ev.text) then
          info.markers[#info.markers + 1] = { flowId = f.id, text = ev.text }
        end
      end
    end
    info.flowNotes[f.id] = notes
  end
  local result = chartcheck.find(info)
  log:line("existing chart:", result.status, result.reason or "")
  if result.status == "ok" then
    local voices = {}
    for _, o in ipairs(doc.voiceOwners(doc.flowById(score, result.flowId))) do
      voices[o.key] = (voices[o.key] or 0) + 1
    end
    result.players = {}
    for _, k in ipairs(result.marker.chartPlayers) do
      result.players[#result.players + 1] = { key = k, role = (voices[k] or 0) >= 2 and "grand" or "treble" }
    end
  end
  return result
end

return findchart
