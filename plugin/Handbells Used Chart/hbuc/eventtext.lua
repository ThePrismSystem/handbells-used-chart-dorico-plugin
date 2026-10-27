-- Parse the tostring() of Dorico's Lua event wrappers into plain tables. Note strings show the sounding
-- pitch, e.g. "kNoteEvent (id:195) at 4, duration 1  G#5 (ends 5)"; grace notes end with their spelling.
local eventtext = {}

local KINDS = {
  kNoteEvent = "note",
  kGraceNoteEvent = "grace",
  kRestEvent = "rest",
  kBarRestEvent = "rest",
  kTextEvent = "text",
  kBarDivisionEvent = "bardivision",
  kBreakEvent = "break",
}

-- "13/2 (6.5)" -> 6.5, "4" -> 4, "1/3 (0.333333)" -> 1/3: an exact fraction wins over the rounded decimal.
local function number(s, from)
  local raw = s:match("^([%-%d%./]+)", from)
  if not raw then return nil end
  local a, b = raw:match("^(%-?%d+)/(%d+)$")
  if a then return tonumber(a) / tonumber(b) end
  return tonumber(raw)
end

local SPELLING = "[A-G][#bx]*%-?%d+"

function eventtext.parse(s)
  local tag = s:match("^(k%a+)")
  local ev = { kind = KINDS[tag] or "other", raw = s }
  ev.id = tonumber(s:match("%(id:(%d+)%)"))
  local _, atEnd = s:find(" at ", 1, true)
  if atEnd then ev.pos = number(s, atEnd + 1) end
  local spelling
  if ev.kind == "note" then
    spelling = s:match("%s(" .. SPELLING .. ") %(ends")
  elseif ev.kind == "grace" then
    spelling = s:match(",%s*(" .. SPELLING .. ")%s*$")
  elseif ev.kind == "text" then
    ev.text = s:match(" : (.-)\n") or s:match(" : (.*)$")
  end
  if spelling then
    ev.spelling = spelling
    local name, octave = spelling:match("^([A-G][#bx]*)(%-?%d+)$")
    ev.name, ev.octave = name, tonumber(octave)
  end
  return ev
end

return eventtext
