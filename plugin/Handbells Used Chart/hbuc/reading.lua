-- Note records for the chart, from two views of the same music. The dumps say which notes exist (every one, with
-- its sounding spelling); the read notes carry noteheads and colours, read either straight from stream.events or
-- from a copy pasted into a scratch flow. The paste merges unisons between voices and adds a temporary note of its
-- own, so the two are matched by (instrument, spelling) pair, not note for note.
local bellname = require("hbuc.bellname")

local reading = {}

-- A note with no notehead set override is drawn with Dorico's default set.
reading.DEFAULT_HEAD = "noteheadset.default"

local function pair(n)
  return tostring(n.instrument) .. "\0" .. tostring(n.spelling)
end

-- records: {pitch, diatonic, head, colour, instrument, grace} in bell space (the sounding spelling, as Dorico's
-- Handbells instrument stores it). unread: how many dumped notes had no read note to take a notehead from; each
-- becomes a record with no pitch, which collect counts as unreadable.
local function tally(notes)
  local counts = {}
  for _, n in ipairs(notes) do counts[pair(n)] = (counts[pair(n)] or 0) + 1 end
  return counts
end

-- Whether every (instrument, spelling) pair was read exactly as often as the dumps list it. stream.events can
-- list fewer events than a stream holds, so the direct read is trusted only when this holds.
function reading.countsMatch(dumpNotes, readNotes)
  local d, r = tally(dumpNotes), tally(readNotes)
  for k, n in pairs(d) do
    if r[k] ~= n then return false end
  end
  for k in pairs(r) do
    if not d[k] then return false end
  end
  return true
end

-- merged (third result): dumped notes beyond the number read for a pair that was read at all. The paste merges a
-- unison between voices of one staff, so a note there may have carried a notehead the read copy lost.
function reading.records(dumpNotes, readNotes)
  local dumpedPairs, readPairs = tally(dumpNotes), tally(readNotes)

  local records = {}
  for _, n in ipairs(readNotes) do
    if dumpedPairs[pair(n)] then
      local p = bellname.fromSpelling(n.spelling)
      local head = n.head or ""
      if head == "" then head = reading.DEFAULT_HEAD end
      records[#records + 1] = {
        pitch = p and p.pitch, diatonic = p and p.diatonic, head = head, colour = n.colour or "",
        instrument = n.instrument, grace = n.grace and true or false,
      }
    end
  end
  local unread = 0
  for _, n in ipairs(dumpNotes) do
    if not readPairs[pair(n)] then
      unread = unread + 1
      records[#records + 1] = { instrument = n.instrument, head = "", colour = "", grace = n.grace and true or false }
    end
  end
  local merged = 0
  for k, n in pairs(dumpedPairs) do
    local got = readPairs[k]
    if got and got < n then merged = merged + (n - got) end
  end
  return records, unread, merged
end

return reading
