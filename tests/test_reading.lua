-- Records from the dumped notes (which notes exist, and whose they are) and the notehead and colour entries a saved
-- copy of the project holds for each, matched by event id.
local reading = require("hbuc.reading")

local function note(id, instrument, spelling, grace)
  return { id = id, instrument = instrument, spelling = spelling, grace = grace or false, instance = 1010 }
end

local function entry(property, value, layout, instance)
  return { property = property, value = value, layout = layout or -1, instance = instance or -1 }
end

local function head(value, layout, instance) return entry("kNoteheadSetOverride", value, layout, instance) end
local function colour(value, layout, instance) return entry("kEventColour", value, layout, instance) end

local function errorOf(fn)
  local ok, err = pcall(fn)
  return not ok and tostring(err) or nil
end

return {
  a_saved_head_and_colour_reach_the_record = function(t)
    local records = reading.records({ note(1, "A", "C5") },
      { [1] = { head("noteheadset.diamondNoteheads"), colour("#c80000") } }, 0)
    t:eq(#records, 1)
    local r = records[1]
    t:eq(r.pitch, 72)
    t:eq(r.diatonic, 35)
    t:eq(r.head, "noteheadset.diamondNoteheads")
    t:eq(r.colour, "#c80000")
    t:eq(r.instrument, "A")
    t:eq(r.grace, false)
  end,
  a_note_with_no_entries_has_the_default_set = function(t)
    local records = reading.records({ note(1, "A", "D5") }, { [1] = {} }, 0)
    t:eq(records[1].head, "noteheadset.default")
    t:eq(reading.DEFAULT_HEAD, "noteheadset.default")
    t:eq(records[1].colour, "")
  end,
  the_full_score_and_the_notes_instance_decide = function(t)
    local saved = { [1] = { head("X", 0, 1010), head("Y") } }
    t:eq(reading.records({ note(1, "A", "C5") }, saved, 0)[1].head, "X", "set for the full score, in this instance")
    t:eq(reading.records({ note(1, "A", "C5") }, saved, 3)[1].head, "Y", "another layout's value doesn't apply")
  end,
  grace_notes_are_kept = function(t)
    local records = reading.records({ note(1, "A", "B5", true) }, { [1] = {} }, 0)
    t:eq(#records, 1)
    t:eq(records[1].grace, true)
  end,
  every_note_is_a_record = function(t)
    local records = reading.records({ note(1, "A", "G#5"), note(2, "A", "G#5"), note(3, "B", "Ab5") },
      { [1] = {}, [2] = {}, [3] = {} }, 0)
    t:eq(#records, 3, "unisons and enharmonics alike")
    t:eq(records[1].pitch, records[3].pitch)
  end,
  a_note_missing_from_the_copy_fails = function(t)
    local err = errorOf(function() return reading.records({ note(7, "A", "C5") }, {}, 0) end)
    t:ok(err and err:find("note 7 is not in the saved copy of the project", 1, true), tostring(err))
  end,
}
