-- Dialog value rules and remembered settings, ported from the Sibelius plugin's Options.mss and
-- NoteHeads.mss. The dialog itself is a separate script; these are the rules both sides of it share.
local constants = require("hbuc.constants")
local json = require("hbuc.json")

local options = {}

function options.trim(value)
  return (tostring(value):gsub("^ +", ""):gsub(" +$", ""))
end

-- Trimmed and given its '#' first. An unparseable value is treated as no colour at all rather than failing
-- the run. Only the length is checked here; canonicalColour reads the digits.
function options.usableColour(value)
  local text = options.trim(value or "")
  if text == "" then return "" end
  if text:sub(1, 1) ~= "#" then text = "#" .. text end
  if #text ~= 7 then return "" end
  return text
end

-- A usable colour as the lower-case #rrggbb Dorico takes; a character that is not a hex digit reads as 0,
-- as the Sibelius plugin's HexDigit does.
function options.canonicalColour(value)
  local text = options.usableColour(value)
  if text == "" then return "" end
  return "#" .. text:sub(2):lower():gsub("[^0-9a-f]", "0")
end

-- The colour a section is drawn in: each coloured instrument has its own field; handbells stay black.
function options.sectionColour(kind, colours)
  if kind == "bells" then return "" end
  return colours[kind] or ""
end

local function listed(names, name)
  if name == nil or name == "" then return false end
  for _, n in ipairs(names) do
    if n == name then return true end
  end
  return false
end
options.listed = listed

-- The value a dropdown opens on: the remembered head while this score still uses it, else the score's own
-- suggestion, else no notehead at all.
function options.preferredHead(names, remembered, fallback)
  if listed(names, remembered) then return remembered end
  if listed(names, fallback) then return fallback end
  return constants.NO_NOTEHEAD
end

function options.headChoiceItems(names)
  local items = { constants.NO_NOTEHEAD }
  for _, n in ipairs(names) do items[#items + 1] = n end
  return items
end

-- Counts one note of a head in a colour ("" for black), keeping each head's colours in the order found.
function options.tallyColour(tally, head, colour)
  local colours = tally[head]
  if not colours then
    colours = {}
    tally[head] = colours
  end
  for _, entry in ipairs(colours) do
    if entry.colour == colour then
      entry.count = entry.count + 1
      return
    end
  end
  colours[#colours + 1] = { colour = colour, count = 1 }
end

-- The colour most of a head's notes carry, or "" when that is black. A tie goes to the colour found first.
function options.mostUsedColour(tally, head)
  local best, bestCount = "", 0
  for _, entry in ipairs(tally[head] or {}) do
    if entry.count > bestCount then
      best, bestCount = entry.colour, entry.count
    end
  end
  return best
end

function options.openingColour(remembered, tally, head)
  if options.trim(remembered or "") ~= "" then return remembered end
  return options.mostUsedColour(tally, head)
end

-- Names are remembered as one pipe-joined string; a pipe in a name is written ~p and a tilde ~~.
function options.pipeList(text)
  local names = {}
  local value = tostring(text or "")
  if value == "" then return names end
  local current, i = {}, 1
  while i <= #value do
    local c = value:sub(i, i)
    if c == "~" then
      local e = value:sub(i + 1, i + 1)
      current[#current + 1] = (e == "p") and "|" or e
      i = i + 2
    elseif c == "|" then
      names[#names + 1] = table.concat(current)
      current = {}
      i = i + 1
    else
      current[#current + 1] = c
      i = i + 1
    end
  end
  names[#names + 1] = table.concat(current)
  return names
end

function options.joinPipe(names)
  local parts = {}
  for i, name in ipairs(names) do
    parts[i] = tostring(name):gsub("~", "~~"):gsub("|", "~p")
  end
  return table.concat(parts, "|")
end

-- The instruments a dialog opens selected: everything offered except what was left out last time.
function options.preselected(offered, excluded)
  local chosen = {}
  for _, name in ipairs(offered) do
    if not listed(excluded, name) then chosen[#chosen + 1] = name end
  end
  return chosen
end

-- What to remember after a run: names this score does not offer keep what was remembered about them; names
-- it offers are remembered as left out exactly when they were not selected. A run with nothing selected
-- changes nothing.
function options.excludedAfterRun(remembered, offered, selected)
  if #selected == 0 then return remembered end
  local excluded = {}
  for _, name in ipairs(remembered) do
    if not listed(offered, name) then excluded[#excluded + 1] = name end
  end
  for _, name in ipairs(offered) do
    if not listed(selected, name) then excluded[#excluded + 1] = name end
  end
  return excluded
end

-- The instruments to remember as written at pitch: names this score does not offer keep what was remembered;
-- names it offers are remembered exactly as they were set this time.
function options.atPitchAfterRun(remembered, offered, chosen)
  local out = {}
  for _, name in ipairs(remembered) do
    if not listed(offered, name) then out[#out + 1] = name end
  end
  for _, name in ipairs(offered) do
    if listed(chosen, name) then out[#out + 1] = name end
  end
  return out
end

-- The notehead two instruments share, or "" when they share none. The no-notehead entry may repeat. With two
-- clashing pairs it names the same one the Sibelius plugin's DuplicateHead does: the earliest instrument a later
-- one repeats.
function options.duplicateHead(heads)
  local kinds = constants.KINDS
  for i, kind in ipairs(kinds) do
    local head = heads[kind] or ""
    if head ~= "" and head ~= constants.NO_NOTEHEAD then
      for j = i + 1, #kinds do
        if heads[kinds[j]] == head then return head end
      end
    end
  end
  return ""
end

function options.chartModeOf(choice)
  if choice == constants.CHART_MODE_SEPARATE then return "separate" end
  return "combined"
end

local function stringField(t, key)
  local v = type(t) == "table" and t[key] or nil
  return type(v) == "string" and v or ""
end

local function kindTable(t)
  local out = {}
  for _, kind in ipairs(constants.KINDS) do out[kind] = stringField(t, kind) end
  return out
end

-- Remembered settings: {excluded and atPitch = pipe strings, mode, newPage, heads/shapes/colours keyed by kind}.
-- newPage is true unless it was turned off.
function options.encodeSettings(s)
  return json.encode({
    excluded = stringField(s, "excluded"),
    atPitch = stringField(s, "atPitch"),
    mode = stringField(s, "mode"),
    newPage = s.newPage ~= false,
    heads = kindTable(s.heads),
    shapes = kindTable(s.shapes),
    colours = kindTable(s.colours),
  })
end

-- A missing or corrupt settings string gives the defaults rather than an error.
function options.decodeSettings(text)
  local ok, raw = pcall(json.decode, text or "")
  if not ok or type(raw) ~= "table" then raw = {} end
  local mode = stringField(raw, "mode")
  return {
    excluded = stringField(raw, "excluded"),
    atPitch = stringField(raw, "atPitch"),
    mode = (mode == "separate") and "separate" or "combined",
    newPage = raw.newPage ~= false,
    heads = kindTable(raw.heads),
    shapes = kindTable(raw.shapes),
    colours = kindTable(raw.colours),
  }
end

return options
