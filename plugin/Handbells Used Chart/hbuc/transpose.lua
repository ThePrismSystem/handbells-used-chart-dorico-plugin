-- "Written as": the bell is the note's sounding pitch on Dorico's Handbells instrument, which sounds an octave
-- above written, and that is what Dorico stores. A part written at pitch (on a Piano or Organ staff) sounds as
-- written, so its bells are an octave above what Dorico stores. Lua cannot read an instrument's transposition
-- (spike/33_instrument_type.lua), so the user says which instruments are written at pitch.
local transpose = {}

local function listed(names, name)
  for _, n in ipairs(names or {}) do
    if n == name then return true end
  end
  return false
end

-- A new list: records of the instruments in names raised an octave, every other record as it was.
function transpose.atPitch(records, names)
  local out = {}
  for i, r in ipairs(records) do
    if type(r.pitch) == "number" and type(r.diatonic) == "number" and listed(names, r.instrument) then
      local copy = {}
      for k, v in pairs(r) do copy[k] = v end
      copy.pitch, copy.diatonic = r.pitch + 12, r.diatonic + 7
      out[i] = copy
    else
      out[i] = r
    end
  end
  return out
end

return transpose
