-- Whether a project holds a chart this plug-in made and may change. Update and remove act only when the marker,
-- the flow's title and the chart players all agree; anything else is refused with the reason.
local constants = require("hbuc.constants")
local marker = require("hbuc.marker")

local chartcheck = {}

local function keySet(list)
  local set = {}
  for _, k in ipairs(list or {}) do set[k] = true end
  return set
end

local function invalid(reason)
  return { status = "invalid", reason = reason }
end

-- info: {markers = {{flowId, text}}, flowTitles = {[flowId] = title}, allTitles = {title...},
-- flowPlayers = {[flowId] = {key...}},
-- flowNotes = {[flowId] = {[key] = notes}}, playerNames = {[key] = name}}. markers holds every text that starts with
-- the marker prefix, from any flow. An "ok" result also lists extras (other players in the chart flow) and strays
-- ({flowId, key}: chart players in other flows), neither holding music, for the writer to take out.
function chartcheck.find(info)
  local found = {}
  for _, m in ipairs(info.markers or {}) do
    if marker.isMarker(m.text) then found[#found + 1] = m end
  end
  if #found == 0 then return { status = "none" } end
  if #found > 1 then return invalid("there is more than one chart marker.") end

  local flowId = found[1].flowId
  local m = marker.decode(found[1].text)
  if not m then return invalid("its marker is damaged or was made by another version of the plug-in.") end
  local chartSet = keySet(m.chartPlayers)

  -- The chart flow's own title where the export numbers its flows; otherwise at least one flow must carry it.
  local title = (info.flowTitles or {})[flowId]
  if title ~= nil and title ~= constants.CHART_FLOW_NAME then
    return invalid(string.format('the flow holding the chart is named "%s", not "%s".', tostring(title),
      constants.CHART_FLOW_NAME))
  end
  if title == nil then
    local present = false
    for _, t in ipairs(info.allTitles or {}) do
      if t == constants.CHART_FLOW_NAME then present = true end
    end
    if not present then return invalid(string.format('no flow is named "%s".', constants.CHART_FLOW_NAME)) end
  end

  -- Every chart player must still be in the chart flow. Others may be there too: Dorico adds a new player to every
  -- flow. They are tolerated while they hold no music there, and taken out again by the next update.
  local notes = info.flowNotes or {}
  local names = info.playerNames or {}
  local flowSet = keySet((info.flowPlayers or {})[flowId])
  for k in pairs(chartSet) do
    if not flowSet[k] then return invalid("the chart flow no longer holds every chart player.") end
  end
  local extras = {}
  for _, k in ipairs((info.flowPlayers or {})[flowId] or {}) do
    if not chartSet[k] then
      if ((notes[flowId] or {})[k] or 0) > 0 then
        return invalid(string.format('the chart flow holds music for "%s".', tostring(names[k] or k)))
      end
      extras[#extras + 1] = k
    end
  end

  -- Chart players may turn up in other flows too (a new flow holds every player), as long as they have no music.
  local flowIds = {}
  for id in pairs(info.flowPlayers or {}) do
    if id ~= flowId then flowIds[#flowIds + 1] = id end
  end
  table.sort(flowIds)
  local strays = {}
  for _, otherId in ipairs(flowIds) do
    for _, k in ipairs(info.flowPlayers[otherId]) do
      if chartSet[k] then
        if ((notes[otherId] or {})[k] or 0) > 0 then
          return invalid(string.format('a chart player has music in the flow "%s".',
            tostring((info.flowTitles or {})[otherId] or otherId)))
        end
        strays[#strays + 1] = { flowId = otherId, key = k }
      end
    end
  end
  return { status = "ok", flowId = flowId, marker = m, extras = extras, strays = strays }
end

return chartcheck
