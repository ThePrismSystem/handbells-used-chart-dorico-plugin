-- "Written as": the bell is the note's sounding pitch on Dorico's Handbells instrument, which sounds an octave
-- above written, and that is what Dorico stores. A part written at pitch (on a Piano or Organ staff) sounds as
-- written, so its bells are an octave above what Dorico stores. Lua cannot read an instrument's transposition
-- (spike/33_instrument_type.lua), but a saved copy's score holds it, and the dialog starts from that.
local dtn = require("hbuc.dtn")

local transpose = {}

-- {[instrument id] = true} for every instrument written as it sounds: one with no octave transposition, where
-- Dorico's Handbells has fixedOctaveTransposition -1.
function transpose.writtenAtPitch(tree)
  local out = {}
  local players = dtn.child(tree, 0, "scorePlayers")
  local list = players and dtn.child(tree, players, "array")
  for _, player in ipairs(list and dtn.children(tree, list) or {}) do
    local instruments = dtn.child(tree, player, "instruments")
    for _, instrument in ipairs(instruments and dtn.children(tree, instruments) or {}) do
      local id = dtn.child(tree, instrument, "instrumentID")
      local transposition = dtn.child(tree, instrument, "transposition")
      local octave = transposition and dtn.child(tree, transposition, "fixedOctaveTransposition")
      if id and (not octave or tonumber(dtn.value(tree, octave)) == 0) then
        out[tonumber(dtn.value(tree, id))] = true
      end
    end
  end
  return out
end

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
