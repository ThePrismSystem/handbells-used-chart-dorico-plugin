-- The chart's identity marker: a hidden text in the chart flow that says the chart is this plug-in's and how
-- to take it out again. Adapted from the Sibelius plugin's Marker.mss. Pipe-separated tokens, escaped as the
-- remembered settings are (~p, ~~), and free of the characters Dorico may read as Markdown:
--   HBUC|1|<chart player ids>|<section count>|<kind,player,columns>...|<4 layout option values>
local constants = require("hbuc.constants")
local options = require("hbuc.options")

local marker = {}

local RESTORE_KEYS = { "flowHeadingBehaviour", "hideEmptyStavesPolicy", "alwaysVisiblePlayers", "playersToShowPlayerName" }
local ENUMS = {
  flowHeadingBehaviour = { kNoFlowHeadings = true, kAddHeadingsAfterFirstFlow = true, kAlwaysInsertHeadings = true },
  hideEmptyStavesPolicy = { kAllSystems = true, kAfterFirstSystem = true, kNever = true },
}
local KIND_OK = {}
for _, kind in ipairs(constants.KINDS) do KIND_OK[kind] = true end

-- "3,4": one or more integer ids, comma-separated (Lua patterns cannot repeat a group, so check by parts).
local function isIds(text)
  if type(text) ~= "string" or text == "" then return false end
  for part in (text .. ","):gmatch("([^,]*),") do
    if not part:match("^%d+$") then return false end
  end
  return true
end

local function isIdList(text)
  return text == "" or isIds(text)
end

function marker.isMarker(text)
  return type(text) == "string" and text:sub(1, #constants.MARKER_PREFIX + 1) == constants.MARKER_PREFIX .. "|"
end

function marker.encode(m)
  local tokens = { constants.MARKER_PREFIX, constants.MARKER_VERSION }
  local ids = {}
  for i, id in ipairs(m.chartPlayers) do ids[i] = tostring(id) end
  tokens[#tokens + 1] = table.concat(ids, ",")
  tokens[#tokens + 1] = tostring(#m.sections)
  for _, s in ipairs(m.sections) do
    tokens[#tokens + 1] = s.kind .. "," .. s.player .. "," .. s.columns
  end
  for _, key in ipairs(RESTORE_KEYS) do tokens[#tokens + 1] = m.restore[key] or "" end
  local text = options.joinPipe(tokens)
  -- A marker the plug-in cannot read back would leave a chart it refuses to update or remove: never write one.
  if not marker.decode(text) then error("refusing to write a chart marker that would not decode: " .. text, 2) end
  return text
end

-- Returns the marker table, or nil for anything that is not a marker this version wrote. A caller that gets
-- nil treats the chart as unidentified and refuses to change it.
function marker.decode(text)
  if not marker.isMarker(text) then return nil end
  local tokens = options.pipeList(text)
  if tokens[2] ~= constants.MARKER_VERSION then return nil end
  if not isIds(tokens[3]) then return nil end
  local count = tonumber(tokens[4] and tokens[4]:match("^%d+$"))
  if not count or count < 1 or #tokens ~= 4 + count + #RESTORE_KEYS then return nil end
  local m = { version = tokens[2], chartPlayers = {}, sections = {}, restore = {} }
  local listed = {}
  for id in tokens[3]:gmatch("%d+") do
    m.chartPlayers[#m.chartPlayers + 1] = tonumber(id)
    listed[tonumber(id)] = true
  end
  for i = 1, count do
    local kind, player, columns = tokens[4 + i]:match("^(%a+),(%d+),(%d+)$")
    if not kind or not KIND_OK[kind] then return nil end
    player, columns = tonumber(player), tonumber(columns)
    -- encode never writes either: every section has a column and sits on one of the chart's own players.
    if columns < 1 or not listed[player] then return nil end
    m.sections[i] = { kind = kind, player = player, columns = columns }
  end
  for j, key in ipairs(RESTORE_KEYS) do
    local value = tokens[4 + count + j]
    if ENUMS[key] then
      if not ENUMS[key][value] then return nil end
    elseif not isIdList(value) then
      return nil
    end
    m.restore[key] = value
  end
  return m
end

return marker
