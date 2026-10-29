-- Takes the noteheads (and colours) Lua couldn't read from a MusicXML export (hbuc.musicxml). A file only counts
-- for a flow when it holds exactly the notes of each player whose noteheads it needs, so an older export of a
-- changed score, another player's part or another piece is never used. Parts pair with players by their notes.
-- Dorico names each part after its player, but two players can share a name.
local bellname = require("hbuc.bellname")
local constants = require("hbuc.constants")
local shapes = require("hbuc.shapes")

local xmlnotes = {}

local M, D = constants.MESSAGES, constants.DIALOG

-- At most this many notes that MusicXML couldn't name are asked about: a few are likely a stray choice of set,
-- and more the arranger's own.
local MOST_TO_ASK = 4
local KEEP_SEPARATE = "separate"

-- Positions to a thousandth of a quarter: the dumps and the file reach a triplet's 1/3 by different sums.
local function key(pos, pitch, diatonic, grace)
  return string.format("%.3f|%s|%s|%s", pos or -1, tostring(pitch), tostring(diatonic), grace and "g" or "")
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

-- {[instrument] = part index} when every instrument with notes in flowDumped has a part holding exactly its notes,
-- else nil. The instruments in optional pair only if such a part is left over. Parts with no notes, and parts left
-- over, don't matter.
function xmlnotes.pair(flowDumped, parsed, optional)
  optional = optional or {}
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
  local function claim(instrument, named)
    local want = fingerprint(keysOf[instrument])
    for i, p in ipairs(parsed.parts) do
      if not used[i] and partPrints[i] == want and (not named or p.name == instrument) then
        pairing[instrument], used[i] = i, true
        return
      end
    end
  end
  -- A part named after its player first, since players can double each other note for note. Then the rest in
  -- order (identical ones pair in turn), the ones that must pair before the optional ones.
  for _, instrument in ipairs(order) do claim(instrument, true) end
  for _, instrument in ipairs(order) do
    if not pairing[instrument] and not optional[instrument] then claim(instrument, false) end
  end
  for _, instrument in ipairs(order) do
    if not pairing[instrument] then
      if not optional[instrument] then return nil end
      claim(instrument, false)
    end
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
-- first file that pairs with it; then the flows no file paired with, the flows one did, and how many changed
-- noteheads a paired file had no note for. Dorico's export can leave a flow out (a flow holding a hand-made chart,
-- for one), so an unpaired flow's changed heads are named as not in MusicXML, which still keeps them apart from
-- plain ones.
function xmlnotes.apply(dumped, read, files)
  local newRead = {}
  for i, n in ipairs(read) do
    local c = {}
    for k, v in pairs(n) do c[k] = v end
    newRead[i] = c
  end
  local missing, paired, unmatched, usedFiles = {}, {}, 0, {}
  for _, flowId in ipairs(xmlnotes.flowsNeeding(read)) do
    -- Only the players with noteheads Lua couldn't read have to pair: another's notes may not be in the file at all
    -- (unpitched percussion, which the reader skips), and their heads were read already. One with only colours Lua
    -- couldn't read takes them from its own part, if the file has one.
    local needed, optional = {}, {}
    for _, n in ipairs(read) do
      if n.flowId == flowId and n.headUnreadable then
        needed[n.instrument] = true
      elseif n.flowId == flowId and n.colourUnreadable then
        optional[n.instrument] = true
      end
    end
    for instrument in pairs(needed) do optional[instrument] = nil end
    local flowDumped = {}
    for _, n in ipairs(dumped) do
      if n.flowId == flowId and (needed[n.instrument] or optional[n.instrument]) then flowDumped[#flowDumped + 1] = n end
    end
    -- Each flow has a file of its own, so a file one flow took can't pair with another holding the same notes.
    local pairing, parsed
    for i, f in ipairs(files) do
      pairing = not usedFiles[i] and xmlnotes.pair(flowDumped, f, optional)
      if pairing then
        parsed, usedFiles[i] = f, true
        break
      end
    end
    local queues = {}
    if pairing then
      paired[#paired + 1] = flowId
      for instrument, i in pairs(pairing) do
        local byKey = {}
        for _, n in ipairs(parsed.parts[i].notes) do
          local k = key(n.pos, n.pitch, n.diatonic, n.grace)
          byKey[k] = byKey[k] or {}
          byKey[k][#byKey[k] + 1] = n
        end
        queues[instrument] = byKey
      end
    else
      missing[#missing + 1] = flowId
    end
    for _, n in ipairs(newRead) do
      if n.flowId == flowId and (n.headUnreadable or n.colourUnreadable) then
        local byKey = queues[n.instrument]
        local x = byKey and take(byKey[noteKey(n)], n.headUnreadable)
        if n.headUnreadable then
          -- one the file has no note for still mustn't read as a plain head
          n.head = x and shapes.fromMusicXML(x.head, x.filled) or shapes.NOT_IN_MUSICXML
          n.headUnreadable = false
          if x then n.bar, n.written = x.bar, x.written end
          if pairing and not x then unmatched = unmatched + 1 end
        end
        if x and n.colourUnreadable and x.colour ~= "" then
          n.colour = x.colour
          n.colourUnreadable = false
        end
      end
    end
  end
  return newRead, missing, paired, unmatched
end

-- The notes apply named as not in MusicXML, in the music's order: flow by flow, then by position.
local function unnamedNotes(read)
  local out, flowRank, at = {}, {}, {}
  for i, n in ipairs(read) do
    flowRank[n.flowId] = flowRank[n.flowId] or i
    if n.head == shapes.NOT_IN_MUSICXML then
      out[#out + 1] = n
      at[n] = i
    end
  end
  table.sort(out, function(a, b)
    if flowRank[a.flowId] ~= flowRank[b.flowId] then return flowRank[a.flowId] < flowRank[b.flowId] end
    if (a.pos or 0) ~= (b.pos or 0) then return (a.pos or 0) < (b.pos or 0) end
    return at[a] < at[b]
  end)
  return out
end

-- The question about a few notes whose noteheads were changed in Dorico to a set MusicXML doesn't record: whether
-- they belong with one of heads, the noteheads the score uses (request.choices). Each note is named by its written
-- pitch and bar, from the file (just the pitch Lua has when the file had no note for it), and by its player when
-- there are two. Nil when there are none, more than MOST_TO_ASK, or no other notehead to offer.
function xmlnotes.groupQuestion(read, heads)
  local notes, offer = unnamedNotes(read), {}
  for _, id in ipairs(heads) do
    if id ~= shapes.NOT_IN_MUSICXML then offer[#offer + 1] = id end
  end
  if #notes == 0 or #notes > MOST_TO_ASK or #offer == 0 then return nil end
  local players, playerCount = {}, 0
  for _, n in ipairs(notes) do
    if not players[n.instrument] then players[n.instrument], playerCount = true, playerCount + 1 end
  end
  local names = {}
  for i, n in ipairs(notes) do
    local name = n.written or n.spelling
    if n.bar then name = string.format(M.musicxmlNoteInBar, name, n.bar) end
    if playerCount > 1 then name = string.format(M.musicxmlNoteOfPlayer, name, n.instrument) end
    names[i] = name
  end
  local one, separate = #notes == 1, constants.NOT_IN_MUSICXML_NAME
  local text = one and string.format(M.musicxmlUnnamedNote, names[1])
    or string.format(M.musicxmlUnnamedNotes, #notes, table.concat(names, ", "))
  local buttons = {}
  if #offer == 1 then
    local name = shapes.displayName(offer[1])
    text = text .. "\n\n" .. string.format(one and M.musicxmlGroupWithOne or M.musicxmlGroupWithMany, name, separate)
    buttons[1] = { id = offer[1], label = string.format(D.includeWith, name) }
  else
    text = text .. "\n\n" .. string.format(one and M.musicxmlGroupChooseOne or M.musicxmlGroupChooseMany, separate)
    for i, id in ipairs(offer) do buttons[i] = { id = id, label = shapes.displayName(id) } end
  end
  buttons[#buttons + 1] = { id = KEEP_SEPARATE, label = D.keepSeparate }
  return { title = D.resultsTitle, text = text, buttons = buttons, cancel = KEEP_SEPARATE }
end

-- Gives the notes apply named as not in MusicXML the head chosen for them, in read itself.
function xmlnotes.group(read, head)
  for _, n in ipairs(read) do
    if n.head == shapes.NOT_IN_MUSICXML then n.head = head end
  end
end

return xmlnotes
