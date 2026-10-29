-- Each note's notehead set and colour in a saved project, and which of a note's entries applies where. A value set
-- by command or in Dorico's UI carries a context: a layout (-1 for every layout) and a block instance (-1 for any).
local dtn = require("hbuc.dtn")
local noteprops = require("hbuc.noteprops")
local zip = require("hbuc.zip")

local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
local DEFAULT = "noteheadset.default"

local function fixtureNotes()
  local f = assert(io.open(here .. "../fixtures/handbells-fixture.dorico", "rb"))
  local bytes = f:read("*a")
  f:close()
  return noteprops.fromTree(dtn.decode(zip.entry(bytes, "score.dtn")))
end

local function head(value, layout, instance)
  return { property = "kNoteheadSetOverride", value = value, layout = layout, instance = instance }
end

local function colour(value, layout, instance)
  return { property = "kEventColour", value = value, layout = layout, instance = instance }
end

return {
  fixture_notes = function(t)
    local notes = fixtureNotes()
    local count = 0
    for _ in pairs(notes) do count = count + 1 end
    t:eq(count, 58, "every note and grace note of the fixture")
    t:ok(notes[200], "the grace note")
    t:eq(noteprops.head(notes[191], 0, 1010), DEFAULT, "a plain note")
    t:eq(noteprops.colour(notes[191], 0, 1010), "", "an uncoloured note")
    t:eq(noteprops.head(notes[209], 0, 1010), "noteheadset.diamondNoteheads", "a red diamond, set from Lua")
    t:eq(noteprops.colour(notes[209], 0, 1010), "#c80000")
  end,
  only_the_two_properties_are_kept = function(t)
    for _, e in ipairs(fixtureNotes()[209]) do
      t:ok(e.property == "kNoteheadSetOverride" or e.property == "kEventColour", e.property)
    end
  end,
  the_full_score_layout_beats_every_layout = function(t)
    local entries = { head("A", -1, -1), head("B", 0, -1) }
    t:eq(noteprops.head(entries, 0, 1010), "B", "local to the full score")
    t:eq(noteprops.head(entries, 3, 1010), "A", "another layout's value doesn't apply")
  end,
  the_notes_instance_beats_any_instance = function(t)
    local entries = { head("C", -1, 1010), head("A", -1, -1) }
    t:eq(noteprops.head(entries, 0, 1010), "C")
    t:eq(noteprops.head(entries, 0, 1011), "A", "another instance's value doesn't apply")
  end,
  only_another_layout = function(t)
    t:eq(noteprops.head({ head("D", 5, -1) }, 0, 1010), DEFAULT, "a part's own notehead")
    t:eq(noteprops.colour({ colour("#ff0000", 5, -1) }, 0, 1010), "", "a part's own colour")
  end,
  default_set_explicitly = function(t)
    t:eq(noteprops.head({ head(DEFAULT, -1, -1) }, 0, 1010), DEFAULT)
  end,
  no_entries = function(t)
    t:eq(noteprops.head({}, 0, 1010), DEFAULT)
    t:eq(noteprops.colour({}, 0, 1010), "")
  end,
  colours_read_as_rrggbb = function(t)
    t:eq(noteprops.colour({ colour("#ff00a050", 0, -1) }, 0, 1010), "#00a050", "with alpha, as a command sets it")
    t:eq(noteprops.colour({ colour("#C80000", -1, -1) }, 0, 1010), "#c80000", "lower case")
    t:eq(noteprops.colour({ colour("red", -1, -1) }, 0, 1010), "", "not a colour")
  end,
}
