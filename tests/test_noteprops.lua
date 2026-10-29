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

-- A tree holding one note (event 7) coloured red, with a context of these {name, value} children.
local function colouredNote(context)
  return dtn.decode(require("dtn_build").tree({ "kScore", nil, { { "NoteEventDefinition", nil, {
    { "eventID", "7" },
    { "propertyTable", nil, { { "entries", nil, { { "entry", nil, {
      { "propertyType", "kEventColour" }, { "value", 'string: "#ffff0000"' },
      { "context", nil, context },
    } } } } } },
  } } } }))
end

-- The children of a context as Dorico 6.2 saves them: a colour's has the offset and the stave type, a notehead's an
-- empty offset and neither.
local OFFSET, NO_OFFSET, STAVE = { "propertyOffset", 'string: "0:0:1:0"' }, { "propertyOffset" },
  { "assignedStaveType", "kNormal" }

local function layout(n)
  return { "layoutIDWithFrameChainID", "steamVariantList:list: {int: " .. n .. "}, {int: -1}, {bool: false}" }
end

local function instance(text)
  return { "blockInstanceID", text }
end

local function errorOf(fn)
  local ok, err = pcall(fn)
  return not ok and tostring(err) or nil
end

local function refused(t, context, label)
  local err = errorOf(function() return noteprops.fromTree(colouredNote(context)) end)
  t:ok(err and err:find("noteprops: ", 1, true), label .. ": " .. tostring(err))
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
  a_colour_context_as_dorico_writes_it = function(t)
    local e = noteprops.fromTree(colouredNote({ OFFSET, layout(3), instance("-1"), STAVE }))[7][1]
    t:eq(e.layout, 3)
    t:eq(e.instance, -1)
    t:eq(e.value, "#ffff0000")
  end,
  a_notehead_context_as_dorico_writes_it = function(t)
    local e = noteprops.fromTree(colouredNote({ NO_OFFSET, layout(-1), instance("1010") }))[7][1]
    t:eq(e.layout, -1)
    t:eq(e.instance, 1010)
  end,
  -- Read as "every layout" or "any instance", a context in a form not seen before could put a part's value on the
  -- full score: the read stops instead.
  a_layout_that_cannot_be_read_fails = function(t)
    refused(t, { { "layoutIDWithFrameChainID", "layout three" }, instance("1010") }, "layout")
  end,
  an_instance_that_cannot_be_read_fails = function(t)
    refused(t, { layout(3), instance("x") }, "instance")
  end,
  a_frame_chain_fails = function(t)
    refused(t, { { "layoutIDWithFrameChainID", "steamVariantList:list: {int: 0}, {int: 2}, {bool: true}" },
      instance("-1") }, "frame chain 2")
  end,
  another_offset_fails = function(t)
    refused(t, { { "propertyOffset", 'string: "1:0:0:0"' }, layout(3), instance("-1") }, "offset")
  end,
  another_stave_type_fails = function(t)
    refused(t, { layout(3), instance("-1"), { "assignedStaveType", "kSmall" } }, "stave type")
  end,
  an_unknown_child_fails = function(t)
    refused(t, { layout(3), instance("-1"), { "voiceIndex", "1" } }, "unknown child")
  end,
  a_context_without_a_layout_fails = function(t)
    refused(t, { OFFSET, instance("1010"), STAVE }, "no layout")
  end,
  a_context_without_an_instance_fails = function(t)
    refused(t, { OFFSET, layout(3), STAVE }, "no instance")
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
