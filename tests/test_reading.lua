-- Records from what the dumps say exists and what could be read with noteheads and colours (directly, or from a
-- pasted copy that merges unisons and carries one temporary note of its own).
local reading = require("hbuc.reading")

local function dumped(instrument, spelling, grace)
  return { instrument = instrument, spelling = spelling, grace = grace or false }
end

local function read(instrument, spelling, head, colour, grace)
  return { instrument = instrument, spelling = spelling, head = head or "", colour = colour or "", grace = grace or false }
end

return {
  read_notes_become_records = function(t)
    local records, unread = reading.records({ dumped("A", "C5") },
      { read("A", "C5", "noteheadset.diamondNoteheads", "#c80000") })
    t:eq(#records, 1)
    t:eq(unread, 0)
    local r = records[1]
    t:eq(r.pitch, 72)
    t:eq(r.diatonic, 35)
    t:eq(r.head, "noteheadset.diamondNoteheads")
    t:eq(r.colour, "#c80000")
    t:eq(r.instrument, "A")
    t:eq(r.grace, false)
  end,
  blank_head_is_the_default_set = function(t)
    local records = reading.records({ dumped("A", "D5") }, { read("A", "D5") })
    t:eq(records[1].head, "noteheadset.default")
    t:eq(reading.DEFAULT_HEAD, "noteheadset.default")
    t:eq(records[1].colour, "")
  end,
  a_colour_lua_cannot_read_is_marked = function(t)
    -- a colour set by command reads back as "", but the note lists the property
    local n = read("A", "C5", "noteheadset.diamondNoteheads")
    n.colourUnreadable = true
    local records = reading.records({ dumped("A", "C5"), dumped("A", "D5") }, { n, read("A", "D5") })
    t:eq(records[1].colour, "")
    t:eq(records[1].colourUnreadable, true)
    t:eq(records[2].colourUnreadable, false, "a note with no colour")
  end,
  grace_notes_are_kept = function(t)
    local records = reading.records({ dumped("A", "B5", true) }, { read("A", "B5", "", "", true) })
    t:eq(#records, 1)
    t:eq(records[1].grace, true)
  end,
  extra_read_notes_are_dropped = function(t)
    local records, unread = reading.records({ dumped("A", "D5") }, { read("A", "D5"), read("A", "C5") })
    t:eq(#records, 1, "the temporary paste note has no dump note")
    t:eq(unread, 0)
  end,
  merged_unisons_are_not_unread = function(t)
    local records, unread = reading.records({ dumped("A", "G#5"), dumped("A", "G#5") }, { read("A", "G#5") })
    t:eq(#records, 1)
    t:eq(unread, 0)
  end,
  missing_pairs_are_unread = function(t)
    local records, unread = reading.records({ dumped("A", "C5"), dumped("B", "E3"), dumped("B", "E3") },
      { read("A", "C5") })
    t:eq(unread, 2)
    t:eq(#records, 3)
    local missing = 0
    for _, r in ipairs(records) do
      if r.pitch == nil then
        missing = missing + 1
        t:eq(r.instrument, "B")
      end
    end
    t:eq(missing, 2)
  end,
  same_spelling_other_instrument_is_separate = function(t)
    local _, unread = reading.records({ dumped("B", "C5") }, { read("A", "C5") })
    t:eq(unread, 1)
  end,
  merged_unisons_are_counted = function(t)
    local records, unread, merged = reading.records(
      { dumped("A", "G#5"), dumped("A", "G#5"), dumped("A", "G#5"), dumped("A", "C5") },
      { read("A", "G#5"), read("A", "C5") })
    t:eq(#records, 2)
    t:eq(unread, 0)
    t:eq(merged, 2, "two of the three G#5s were read as one")
  end,
  counts_match_only_when_every_pair_does = function(t)
    local d = { dumped("A", "G#5"), dumped("A", "G#5"), dumped("B", "C5") }
    t:eq(reading.countsMatch(d, { read("A", "G#5"), read("A", "G#5"), read("B", "C5") }), true)
    t:eq(reading.countsMatch(d, { read("A", "G#5"), read("B", "C5") }), false, "events listed fewer notes")
    t:eq(reading.countsMatch(d, { read("A", "G#5"), read("A", "G#5"), read("A", "G#5"), read("B", "C5") }), false)
  end,
  enharmonics_are_different_pairs = function(t)
    local records, unread = reading.records({ dumped("A", "G#5"), dumped("A", "Ab5") },
      { read("A", "G#5"), read("A", "Ab5") })
    t:eq(#records, 2)
    t:eq(unread, 0)
    t:eq(records[1].pitch, records[2].pitch)
  end,
}
