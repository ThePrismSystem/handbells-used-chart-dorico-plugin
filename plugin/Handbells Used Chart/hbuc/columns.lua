-- Chart columns and octave stacks, ported from the Sibelius plugin's Columns.mss.
-- Bells above C7 stack over the column of the same spelling an octave or two down; bells below C3 hang under
-- the column an octave up. Two bells with the same letter and alteration share a diatonic step modulo 7, so
-- an anchor is found by (pitch - offset, diatonic - offsetDiatonic), which matches spelling as well as pitch.
local columns = {}

local function filterRegion(entries, region)
  local out = {}
  for _, e in ipairs(entries) do
    if e.region == region then out[#out + 1] = e end
  end
  return out
end

local function combine(a, b)
  local out = {}
  for _, e in ipairs(a) do out[#out + 1] = e end
  for _, e in ipairs(b) do out[#out + 1] = e end
  return out
end

-- Builds columns around anchors, attaching each entry of attachmentLists[i] to the anchor offsets[i]
-- semitones away with the same spelling. An entry with no anchor becomes its own column, sorted as though
-- its anchor existed, so reading order stays ascending.
local function anchorColumns(anchors, attachmentLists, offsets)
  local cols, index = {}, {}
  for _, a in ipairs(anchors) do
    local key = a.pitch .. ":" .. a.diatonic
    cols[#cols + 1] = { sortPitch = a.pitch, sortAlter = -a.alter, notes = { a } }
    index[key] = #cols
  end
  for i, list in ipairs(attachmentLists) do
    local offset = offsets[i]
    local offsetDiatonic = math.floor(offset / 12 * 7)
    for _, e in ipairs(list) do
      local anchorPitch, anchorDiatonic = e.pitch - offset, e.diatonic - offsetDiatonic
      local key = anchorPitch .. ":" .. anchorDiatonic
      local slot = index[key]
      if slot then
        local notes = cols[slot].notes
        notes[#notes + 1] = e
      else
        cols[#cols + 1] = { sortPitch = anchorPitch, sortAlter = -e.alter, notes = { e } }
        index[key] = #cols
      end
    end
  end
  table.sort(cols, function(a, b)
    if a.sortPitch ~= b.sortPitch then return a.sortPitch < b.sortPitch end
    return a.sortAlter < b.sortAlter
  end)
  local out = {}
  for _, c in ipairs(cols) do
    table.sort(c.notes, function(a, b) return a.pitch < b.pitch end)
    out[#out + 1] = c.notes
  end
  return out
end

local function singleColumns(list)
  local out = {}
  for _, e in ipairs(list) do out[#out + 1] = { e } end
  return out
end

-- entries: collect entries ({pitch, diatonic, alter, region, ...}). singleStaff: true for an instrument
-- charted on one treble staff, where everything anchors on that staff and nothing goes to a bass staff that
-- is never drawn.
function columns.build(entries, singleStaff)
  local trebleStaff = filterRegion(entries, "trebleStaff")
  local trebleRow1 = filterRegion(entries, "trebleRow1")
  local trebleRow2 = filterRegion(entries, "trebleRow2")
  local bassStaff = filterRegion(entries, "bassStaff")
  local bassRow1 = filterRegion(entries, "bassRow1")
  local bassRow2 = filterRegion(entries, "bassRow2")

  if singleStaff then
    local treble = anchorColumns(combine(bassStaff, trebleStaff), { trebleRow1, trebleRow2, bassRow1, bassRow2 },
      { 12, 24, -12, -24 })
    return { treble = treble, bass = {}, length = #treble }
  end

  local treble = anchorColumns(trebleStaff, { trebleRow1, trebleRow2 }, { 12, 24 })
  local bass = anchorColumns(bassRow1, { bassRow2 }, { -12 })
  for _, c in ipairs(singleColumns(bassStaff)) do bass[#bass + 1] = c end
  return { treble = treble, bass = bass, length = math.max(#treble, #bass) }
end

-- Silver melody bells are a treble set, conventionally charted on one staff.
function columns.usesOneStaff(kind)
  return kind == "smbs"
end

return columns
