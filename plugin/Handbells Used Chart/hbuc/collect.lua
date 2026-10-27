-- Groups note records into the distinct bells each instrument uses, ported from the Sibelius plugin's
-- Collect.mss. Which notehead means which instrument is the user's choice: heads[kind] is a Dorico notehead
-- set id picked in the dialog, or NO_NOTEHEAD / "" for an instrument the piece does not use.
local bellname = require("hbuc.bellname")
local constants = require("hbuc.constants")

local collect = {}

-- Ascending by pitch, then double sharp through double flat, the order published charts print
-- enharmonic pairs in.
local function sortBells(list)
  table.sort(list, function(a, b)
    if a.pitch ~= b.pitch then return a.pitch < b.pitch end
    return a.alter > b.alter
  end)
  return list
end

-- A fraction, NaN or infinity names no bell, and bellname.nameOf would raise on one.
local function isWhole(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge and math.floor(n) == n
end

-- records: {pitch, diatonic, head, colour, instrument} in bell space. heads: {bells=id, chimes=id, ...}.
function collect.bells(records, heads)
  heads = heads or {}
  local chosen = {}
  for _, kind in ipairs(constants.KINDS) do
    local head = heads[kind] or ""
    -- The no-notehead entry is reduced to the empty choice, which matches nothing.
    if head == constants.NO_NOTEHEAD then head = "" end
    chosen[kind] = head
  end

  local out = { unknown = 0, unknownNames = {}, unreadable = 0, outOfRange = {} }
  local seen = {}
  for _, kind in ipairs(constants.KINDS) do
    out[kind] = {}
    seen[kind] = {}
  end
  local seenUnknown, seenOutOfRange = {}, {}

  for _, record in ipairs(records) do
    local pitch, diatonic = record.pitch, record.diatonic
    if not isWhole(pitch) or not isWhole(diatonic) then
      out.unreadable = out.unreadable + 1
    else
      local head = record.head or ""
      local kind = ""
      -- Guarded on the choice, not just the head: an empty choice must not match a head that failed to read.
      for _, k in ipairs(constants.KINDS) do
        if chosen[k] ~= "" and head == chosen[k] then kind = k end
      end
      if kind == "" then
        out.unknown = out.unknown + 1
        -- Named, not just counted: the name is the one to pick in the dropdown.
        if head ~= "" and not seenUnknown[head] then
          seenUnknown[head] = true
          out.unknownNames[#out.unknownNames + 1] = head
        end
      else
        local bell = bellname.nameOf(pitch, diatonic)
        local region = bellname.regionOf(diatonic)
        if region == "" then
          if not seenOutOfRange[bell.name] then
            seenOutOfRange[bell.name] = true
            out.outOfRange[#out.outOfRange + 1] = bell.name
          end
        else
          -- Added the first time that exact spelling turns up, counted every time.
          local key = pitch .. ":" .. diatonic
          local found = seen[kind][key]
          if not found then
            bell.region = region
            bell.count = 0
            seen[kind][key] = bell
            out[kind][#out[kind] + 1] = bell
            found = bell
          end
          found.count = found.count + 1
        end
      end
    end
  end

  for _, kind in ipairs(constants.KINDS) do sortBells(out[kind]) end
  return out
end

return collect
