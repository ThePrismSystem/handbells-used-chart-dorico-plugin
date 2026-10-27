-- Instrument names, ported from the Sibelius plugin's Instruments.mss. In Dorico an instrument is known by
-- the name the text export gives its voice streams, in score order.
local instruments = {}

-- Repeats become "Name (2)", "Name (3)", never a number another instrument already uses.
function instruments.unique(names)
  local original, used, out = {}, {}, {}
  for _, name in ipairs(names) do original[name] = true end
  for i, name in ipairs(names) do
    if used[name] then
      local n = 2
      local candidate = name .. " (" .. n .. ")"
      while original[candidate] or used[candidate] do
        n = n + 1
        candidate = name .. " (" .. n .. ")"
      end
      name = candidate
    end
    used[name] = true
    out[i] = name
  end
  return out
end

local function listed(names, name)
  for _, n in ipairs(names) do
    if n == name then return true end
  end
  return false
end

-- The records whose instrument is one of names.
function instruments.recordsFor(records, names)
  local kept = {}
  for _, record in ipairs(records) do
    if listed(names, record.instrument) then kept[#kept + 1] = record end
  end
  return kept
end

-- The instruments of all (score order) that names asks for, whatever order names is in.
function instruments.named(all, names)
  local chosen = {}
  for _, name in ipairs(all) do
    if listed(names, name) then chosen[#chosen + 1] = name end
  end
  return chosen
end

return instruments
