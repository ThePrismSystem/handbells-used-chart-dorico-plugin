-- Which instrument owns each voice stream? Dorico's FlowInstrument.streams only works for the
-- first instrument, so we ask the text export instead: put a marker text in every voice stream,
-- run File.Export.Text, read each marker's Instrument column, then delete the markers.
local streammap = {}

streammap.PREFIX = "HBUCMAP"

-- The plug-in's quote-aware CSV reader: a quoted field may hold a newline, which a line-by-line split would break.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
local textexport = dofile(here .. "../../plugin/Handbells Used Chart/hbuc/textexport.lua")

-- csv: File.Export.Text output. Returns its data rows as tables keyed by the header's column names.
streammap.csvRecords = textexport.csvRecords

-- csv: File.Export.Text output. Returns {[streamId] = instrumentName} for texts starting with prefix.
function streammap.parseExport(csv, prefix)
  return textexport.streamOwners(csv, prefix)
end

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- Number of marker texts still present in flow's voice streams (0 after owners() returns or fails).
function streammap.leftoverMarkers(flow)
  local n = 0
  for _, s in ipairs(flow.voiceStreams) do
    for _, e in ipairs(s.events) do
      if tostring(e):find(streammap.PREFIX, 1, true) then n = n + 1 end
    end
  end
  return n
end

local function deleteMarkers(flow)
  for _, s in ipairs(flow.voiceStreams) do
    -- match by text: the wrapper returned by createText may not be the same object as the stream's event
    for _, e in ipairs(s.events) do
      if tostring(e):find(streammap.PREFIX, 1, true) then s:delete(e) end
    end
  end
end

-- Returns {[streamId] = instrumentName} for every voice stream of flow. Leaves no markers behind,
-- whether it succeeds or fails.
function streammap.owners(app, flow)
  local base = require("rundir")() .. "streammap"
  os.remove(base .. ".csv")
  local ok, err = pcall(function()
    local zero, one = DoCore.RhythmicLength(0), DoCore.RhythmicLength(1)
    for _, s in ipairs(flow.voiceStreams) do
      s:createText(zero, one, streammap.PREFIX .. s.id)
    end
    app:doCommand("File.Export.Text?File=" .. base .. ".txt&Show=false")
  end)
  deleteMarkers(flow)
  local left = streammap.leftoverMarkers(flow)
  if not ok then error(err, 0) end
  if left > 0 then error(left .. " stream-map markers could not be removed") end
  local csv = readFile(base .. ".csv")
  if not csv then error("File.Export.Text wrote no " .. base .. ".csv") end
  return streammap.parseExport(csv, streammap.PREFIX)
end

return streammap
