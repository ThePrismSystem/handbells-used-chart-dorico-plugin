-- Note records for the chart. The dumps say which notes exist (every one, with its sounding spelling and its block
-- instance), and a saved copy of the project gives each one's notehead set and colour (hbuc.noteprops), matched by
-- event id.
local bellname = require("hbuc.bellname")
local noteprops = require("hbuc.noteprops")

local reading = {}

-- A note with no notehead set override is drawn with Dorico's default set.
reading.DEFAULT_HEAD = "noteheadset.default"

-- notes: {{id, instance, instrument, spelling, grace}}; saved: {[eventId] = entries}; layoutId: the full score's.
-- Returns records {pitch, diatonic, head, colour, instrument, grace} in bell space (the sounding spelling, as
-- Dorico's Handbells instrument stores it). A spelling bellname can't read gives a record with no pitch, which
-- collect counts as unreadable.
function reading.records(notes, saved, layoutId)
  local records = {}
  for i, n in ipairs(notes) do
    local entries = saved[n.id]
    if not entries then error("note " .. tostring(n.id) .. " is not in the saved copy of the project", 0) end
    local p = bellname.fromSpelling(n.spelling)
    records[i] = {
      pitch = p and p.pitch, diatonic = p and p.diatonic,
      head = noteprops.head(entries, layoutId, n.instance), colour = noteprops.colour(entries, layoutId, n.instance),
      instrument = n.instrument, grace = n.grace and true or false,
    }
  end
  return records
end

return reading
