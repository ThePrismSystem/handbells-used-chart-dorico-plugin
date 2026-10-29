-- stream:dump() text as events. On real music this is the only complete view of a voice stream: stream.events
-- throws on lyrics, slurs, playing techniques and other events with no Lua class (docs/dorico-lua-guide.md,
-- section 3). Each event line is "<pos> (<pos>)[ dur: <d>]: <tostring(event)>". A text event is followed by its own
-- further lines, then a " (<paragraph style>)" line.
local eventtext = require("hbuc.eventtext")

local dump = {}

local EVENT_START = ": (k%a+ %(id:%d+%))"

-- The text after " : " on the first line, plus any lines before the paragraph style line.
local function textOf(first, rest)
  local text = first:match(" : (.*)$") or ""
  local body = {}
  for i, line in ipairs(rest) do
    if not (i == #rest and line:match("^ %(.*%)$")) then body[#body + 1] = line end
  end
  if #body > 0 then text = text .. "\n" .. table.concat(body, "\n") end
  return text
end

-- Each event carries the block instance it sits in ("Start block id" is an instance id, despite its name).
function dump.parse(text)
  local out = { events = {} }
  local current, rest, instance
  local function finish()
    if not current then return end
    local ev = eventtext.parse(current)
    if ev.kind == "text" then ev.text = textOf(current, rest) end
    ev.instance = instance
    out.events[#out.events + 1] = ev
    current, rest = nil, nil
  end
  for line in (text or ""):gmatch("([^\n]*)\n?") do
    local at = line:find(EVENT_START)
    if at then
      finish()
      current, rest = line:sub(at + 2), {}
    elseif line:match("^Start block id: %d+") then
      finish()
      instance = tonumber(line:match("^Start block id: (%d+)"))
    elseif line:match("^%-%-%-%-") then
      finish()
    elseif current and line ~= "" then
      rest[#rest + 1] = line
    end
  end
  finish()
  return out
end

-- The note and grace note events, in dump order.
function dump.notes(parsed)
  local notes = {}
  for _, ev in ipairs(parsed.events) do
    if (ev.kind == "note" or ev.kind == "grace") and ev.spelling then
      notes[#notes + 1] = { spelling = ev.spelling, grace = ev.kind == "grace", id = ev.id, pos = ev.pos,
        instance = ev.instance }
    end
  end
  return notes
end

return dump
