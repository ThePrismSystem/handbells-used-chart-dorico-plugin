-- Takes the noteheads (and colours) Lua couldn't read from a MusicXML export (hbuc.musicxml). A file only counts
-- for a flow when it holds exactly that flow's notes, player by player, so an older export of a changed score, a
-- part's file or another piece is never used. Parts pair with players by their notes. Dorico names each part after
-- its player, but two players can share a name.
local bellname = require("hbuc.bellname")
local shapes = require("hbuc.shapes")

local xmlnotes = {}

-- Positions to a thousandth of a quarter: the dumps and the file reach a triplet's 1/3 by different sums.
local function key(pos, pitch, diatonic, grace)
  return string.format("%.3f|%s|%s|%s", pos or -1, tostring(pitch), tostring(diatonic), tostring(grace and true))
end

local function noteKey(n)
  local p = bellname.fromSpelling(n.spelling)
  return key(n.pos, p and p.pitch, p and p.diatonic, n.grace)
end

local function fingerprint(keys)
  local sorted = {}
  for i, k in ipairs(keys) do sorted[i] = k end
  table.sort(sorted)
  return table.concat(sorted, "\n")
end

-- The flows, in first-seen order, holding a note whose notehead Lua couldn't read.
function xmlnotes.flowsNeeding(read)
  local out, seen = {}, {}
  for _, n in ipairs(read) do
    if n.headUnreadable and not seen[n.flowId] then
      seen[n.flowId] = true
      out[#out + 1] = n.flowId
    end
  end
  return out
end

-- {[instrument] = part index} when every instrument with notes in flowDumped has a part holding exactly its notes
-- (identical ones pair in order), else nil. Parts with no notes, and parts left over, don't matter.
function xmlnotes.pair(flowDumped, parsed)
  local order, keysOf = {}, {}
  for _, n in ipairs(flowDumped) do
    if not keysOf[n.instrument] then
      keysOf[n.instrument] = {}
      order[#order + 1] = n.instrument
    end
    local ks = keysOf[n.instrument]
    ks[#ks + 1] = noteKey(n)
  end
  local partPrints = {}
  for i, p in ipairs(parsed.parts) do
    local ks = {}
    for _, n in ipairs(p.notes) do ks[#ks + 1] = key(n.pos, n.pitch, n.diatonic, n.grace) end
    partPrints[i] = #ks > 0 and fingerprint(ks) or nil
  end
  local pairing, used = {}, {}
  for _, instrument in ipairs(order) do
    local want = fingerprint(keysOf[instrument])
    for i = 1, #parsed.parts do
      if not used[i] and partPrints[i] == want then
        pairing[instrument], used[i] = i, true
        break
      end
    end
    if not pairing[instrument] then return nil end
  end
  return pairing
end

-- The file note for a read note: the first of that position, pitch and grace not yet taken, preferring one with a
-- notehead when the read note's head was changed (a unison of a plain and a changed note).
local function take(queue, wantHead)
  if not queue then return nil end
  local at = 1
  if wantHead then
    for i, n in ipairs(queue) do
      if n.head then at = i break end
    end
  end
  return table.remove(queue, at)
end

-- A copy of read in which each flow needing a file takes the noteheads and colours Lua couldn't read from the
-- first file that pairs with it; then the flows no file paired with, and the flows one did. Dorico's export can
-- leave a flow out (Goodbye Blue Sky's hand-made chart flow wasn't exported), so an unpaired flow's changed heads
-- are named as not in MusicXML, which still keeps them apart from plain ones.
function xmlnotes.apply(dumped, read, files)
  local newRead = {}
  for i, n in ipairs(read) do
    local c = {}
    for k, v in pairs(n) do c[k] = v end
    newRead[i] = c
  end
  local missing, paired = {}, {}
  for _, flowId in ipairs(xmlnotes.flowsNeeding(read)) do
    -- Only the players with notes Lua couldn't read have to pair: another's notes may not be in the file at all
    -- (unpitched percussion, which the reader skips), and their heads were read already.
    local needed = {}
    for _, n in ipairs(read) do
      if n.flowId == flowId and (n.headUnreadable or n.colourUnreadable) then needed[n.instrument] = true end
    end
    local flowDumped = {}
    for _, n in ipairs(dumped) do
      if n.flowId == flowId and needed[n.instrument] then flowDumped[#flowDumped + 1] = n end
    end
    local pairing, parsed
    for _, f in ipairs(files) do
      pairing = xmlnotes.pair(flowDumped, f)
      if pairing then
        parsed = f
        break
      end
    end
    if not pairing then
      missing[#missing + 1] = flowId
      for _, n in ipairs(newRead) do
        if n.flowId == flowId and n.headUnreadable then
          n.head = shapes.NOT_IN_MUSICXML
          n.headUnreadable = false
        end
      end
    else
      paired[#paired + 1] = flowId
      local queues = {}
      for instrument, i in pairs(pairing) do
        local byKey = {}
        for _, n in ipairs(parsed.parts[i].notes) do
          local k = key(n.pos, n.pitch, n.diatonic, n.grace)
          byKey[k] = byKey[k] or {}
          byKey[k][#byKey[k] + 1] = n
        end
        queues[instrument] = byKey
      end
      for _, n in ipairs(newRead) do
        if n.flowId == flowId and (n.headUnreadable or n.colourUnreadable) and queues[n.instrument] then
          local x = take(queues[n.instrument][noteKey(n)], n.headUnreadable)
          if n.headUnreadable then
            -- one the file has no note for still mustn't read as a plain head
            n.head = x and shapes.fromMusicXML(x.head, x.filled) or shapes.NOT_IN_MUSICXML
            n.headUnreadable = false
          end
          if x and n.colourUnreadable and x.colour ~= "" then
            n.colour = x.colour
            n.colourUnreadable = false
          end
        end
      end
    end
  end
  return newRead, missing, paired
end

return xmlnotes
