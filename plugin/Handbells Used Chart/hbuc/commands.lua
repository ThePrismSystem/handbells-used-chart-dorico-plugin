-- Dorico command strings, in the forms proved in Dorico (docs/dorico-lua-guide.md, sections 5 and 6). Parameter
-- values are escaped the way Dorico reads them; names (and the option dictionary's items) are refused outright if
-- they hold '&', '=' or a line break.
local commands = {}

local function checkParam(text, what)
  local s = tostring(text)
  if s:find("[&=\n\r]") then
    error("command " .. what .. " cannot contain '&', '=' or a line break: " .. s, 3)
  end
  return s
end

-- A parameter value as Dorico reads it (spike/30_param_escapes.lua): a backslash escapes the next character, so
-- "\&" is an ampersand and "\\" a backslash; "=" and any Unicode pass through as they are.
local function encodeValue(text)
  -- tostring would send the word "nil" to Dorico.
  if text == nil then error("a command value is missing", 3) end
  local s = tostring(text)
  if s:find("[\n\r]") then error("a command value cannot contain a line break: " .. s, 3) end
  return (s:gsub("\\", "\\\\"):gsub("&", "\\&"))
end

-- A Dorico id is a whole number (a digit string will do). Anything else would select or delete the wrong thing,
-- or nothing, without a word from Dorico.
local function id(value, what)
  local ok = (type(value) == "number" and value == math.floor(value) and value > -math.huge and value < math.huge)
    or (type(value) == "string" and value:match("^%-?%d+$"))
  if not ok then error("command " .. what .. " is not an id: " .. tostring(value), 3) end
  return value
end

-- name?key=value&key=value, params in the order given.
function commands.build(name, params)
  local parts = {}
  for i, kv in ipairs(params) do
    parts[i] = checkParam(kv[1], "parameter name") .. "=" .. encodeValue(kv[2])
  end
  if #parts == 0 then return name end
  return name .. "?" .. table.concat(parts, "&")
end

-- One dictionary item as Dorico logs it: backslash, quote and comma escaped.
local function quote(value)
  local s = checkParam(value, "option value")
  s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub(",", "\\,")
  return '{string: "' .. s .. '"}'
end

local function dictionary(values)
  local paths = {}
  for path in pairs(values) do paths[#paths + 1] = path end
  table.sort(paths)
  local items = {}
  for _, path in ipairs(paths) do
    items[#items + 1] = quote(path)
    items[#items + 1] = quote(values[path])
  end
  return "list: " .. table.concat(items, "\\, ")
end

-- Full-score (or any) layout options: Project.Layout.SetOptions, the form the Remote API's setoptions logs.
function commands.layoutOptions(openScoreID, layoutId, values)
  return "Project.Layout.SetOptions?Dictionary=" .. dictionary(values)
    .. "&OpenScoreID=" .. id(openScoreID, "score id") .. "&LayoutIDArray=" .. id(layoutId, "layout id")
end

-- One flow's notation options. Always given the flow id explicitly: the Remote API's flowIDs hit flow 0.
function commands.flowNotationOptions(openScoreID, flowId, values)
  return "Project.Flow.SetNotationOptions?Dictionary=" .. dictionary(values)
    .. "&OpenScoreID=" .. id(openScoreID, "score id") .. "&FlowIDArray=" .. id(flowId, "flow id")
end

-- blockId is the id of the block holding the event, from hbuc.dorico.doc.blockIdOf. The "Start block id" that
-- stream:dump() prints is an instance id.
function commands.select(flowId, eventId, blockId)
  return commands.build("EventEdit.Select", {
    { "FlowID", id(flowId, "flow id") }, { "EventID", id(eventId, "event id") },
    { "EventBlockID", id(blockId, "block id") },
  })
end

function commands.renamePlayer(playerId, name)
  return commands.build("Project.Player.Rename",
    { { "PlayerID", id(playerId, "player id") }, { "Name", name }, { "ShortName", name } })
end

-- The name alone: the short name stays as it is.
function commands.renamePlayerName(playerId, name)
  return commands.build("Project.Player.Rename", { { "PlayerID", id(playerId, "player id") }, { "Name", name } })
end

function commands.renameFlow(flowId, name)
  return commands.build("Project.Flow.Rename", { { "FlowID", id(flowId, "flow id") }, { "Name", name } })
end

-- A single flow id is the whole array: proven with FlowIDArray=<id>.
function commands.moveFlowToStart(flowId)
  return commands.build("Project.Flows.MoveToStart", { { "FlowIDArray", id(flowId, "flow id") } })
end

-- kSetupMode or kWriteMode. Deleting a flow needs Setup mode.
function commands.setMode(mode)
  return commands.build("Window.SwitchMode", { { "WindowMode", mode } })
end

-- Silent (docs/dorico-lua-guide.md, section 5).
function commands.deleteLayout(layoutId)
  return commands.build("Project.Layouts.Delete", { { "LayoutIDArray", id(layoutId, "layout id") } })
end

-- Dorico asks the user to confirm.
function commands.deleteFlow(flowId)
  return commands.build("Project.Flows.Delete", { { "FlowIDArray", id(flowId, "flow id") } })
end

-- At the selected note; "X" is an open meter.
function commands.timeSignature(definition)
  return commands.build("NoteInput.CreateTimeSignature", { { "Definition", definition } })
end

return commands
