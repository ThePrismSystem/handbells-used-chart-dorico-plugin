-- Chart players (slots), reuse on update, and what each section writes where.
local chartlayout = require("hbuc.chartlayout")
local plan = require("hbuc.plan")
local constants = require("hbuc.constants")

local NONE, MATCH = constants.NO_NOTEHEAD, constants.SHAPE_MATCH
local NORMAL, DIAMOND, SQUARE = "noteheadset.default", "noteheadset.diamondNoteheads", "noteheadset.rectangular"
local HEADS = { bells = NORMAL, chimes = DIAMOND, smbs = SQUARE, pf = NONE, whitechapel = NONE }

local function r(pitch, diatonic, head, instrument)
  return { pitch = pitch, diatonic = diatonic, head = head, colour = "", instrument = instrument or "A" }
end

local function choices(over)
  local c = {
    shapes = { bells = MATCH, chimes = MATCH, smbs = MATCH, pf = MATCH, whitechapel = MATCH },
    colours = { chimes = "", smbs = "", pf = "", whitechapel = "" },
    heads = HEADS,
    headNames = { [NORMAL] = "Default Noteheads", [DIAMOND] = "Diamond Noteheads", [SQUARE] = "Rectangular Noteheads" },
  }
  for k, v in pairs(over or {}) do c[k] = v end
  return c
end

local function sectionsOf(records, names, mode)
  return plan.build(records, { heads = HEADS, instruments = names or { "A" }, mode = mode or "combined" }).sections
end

return {
  instrument_constants = function(t)
    t:eq(constants.GRAND_INSTRUMENT, "instrument.pitchedpercussion.handbells")
    t:eq(constants.TREBLE_INSTRUMENT, "instrument.pitchedpercussion.glockenspiel")
  end,
  roles = function(t)
    t:eq(chartlayout.roleOf("smbs"), "treble")
    t:eq(chartlayout.roleOf("bells"), "grand")
    t:eq(chartlayout.roleOf("whitechapel"), "grand")
  end,
  combined_bells_and_smbs_use_two_slots = function(t)
    local sections = sectionsOf({ r(72, 35, NORMAL), r(84, 42, SQUARE) })
    local slots = chartlayout.slots(sections)
    t:eq(#slots, 2)
    t:eq(slots[1].role, "grand")
    t:eq(slots[2].role, "treble")
    t:eq(sections[1].slot, 1)
    t:eq(sections[2].slot, 2)
  end,
  combined_bells_and_chimes_share_a_grand_slot = function(t)
    local sections = sectionsOf({ r(72, 35, NORMAL), r(74, 36, DIAMOND) })
    local slots = chartlayout.slots(sections)
    t:eq(#slots, 1)
    t:eq(sections[1].slot, 1)
    t:eq(sections[2].slot, 1)
  end,
  separate_mode_gives_each_instrument_its_own_slots = function(t)
    local sections = sectionsOf({ r(72, 35, NORMAL, "A"), r(84, 42, SQUARE, "A"), r(74, 36, NORMAL, "B") },
      { "A", "B" }, "separate")
    local slots = chartlayout.slots(sections)
    t:eq(#slots, 3)
    t:eq(slots[1].role .. ":" .. slots[1].owner, "grand:A")
    t:eq(slots[2].role .. ":" .. slots[2].owner, "treble:A")
    t:eq(slots[3].role .. ":" .. slots[3].owner, "grand:B")
  end,
  assign_reuses_by_role_and_reports_surplus = function(t)
    local a = chartlayout.assign({ { role = "grand" }, { role = "treble" } },
      { { key = 7, role = "grand" }, { key = 8, role = "treble" }, { key = 9, role = "grand" } })
    t:eq(a.keys[1], 7)
    t:eq(a.keys[2], 8)
    t:eq(#a.surplus, 1)
    t:eq(a.surplus[1], 9)
    local b = chartlayout.assign({ { role = "grand" }, { role = "grand" }, { role = "treble" } },
      { { key = 7, role = "grand" } })
    t:eq(b.keys[1], 7)
    t:eq(b.keys[2], false)
    t:eq(b.keys[3], false)
    t:eq(#b.surplus, 0)
    t:eq(chartlayout.assign({ { role = "grand" } }, nil).keys[1], false, "a new chart reuses nothing")
  end,
  sections_start_after_each_other = function(t)
    -- three treble-staff bells (D5, E5, F5): three columns; bass columns would share positions with them
    local sections = sectionsOf({ r(74, 36, NORMAL), r(76, 37, NORMAL), r(77, 38, NORMAL), r(74, 36, DIAMOND) })
    chartlayout.slots(sections)
    local built = chartlayout.build(sections, choices())
    t:eq(built.sections[1].start, 0)
    t:eq(built.sections[1].columns, 3)
    t:eq(built.sections[2].start, 3)
    t:eq(built.sections[2].label, "Handchimes Used: 1")
  end,
  grand_spellings_are_the_bell_spelling = function(t)
    local sections = sectionsOf({ r(80, 39, NORMAL), r(72, 35, NORMAL) })
    chartlayout.slots(sections)
    local s = chartlayout.build(sections, choices()).sections[1]
    t:eq(s.treble[1][1], "G#5", "bell G#5 sits on the treble staff")
    t:eq(s.bass[1][1], "C5", "bell C5 sits on the bass staff")
  end,
  treble_spellings_are_an_octave_up = function(t)
    local sections = sectionsOf({ r(84, 42, SQUARE) })
    chartlayout.slots(sections)
    local s = chartlayout.build(sections, choices()).sections[1]
    t:eq(s.kind, "smbs")
    t:eq(s.treble[1][1], "C7", "the Glockenspiel sounds two octaves up: written C5 for bell C6")
    t:eq(#s.bass, 0)
  end,
  smbs_above_midi_127_are_skipped_with_a_warning = function(t)
    -- bell G8 (115) is written as sounding G9 (127) on the Glockenspiel; G#8 would need 128, which MIDI lacks
    local sections = sectionsOf({ r(115, 60, SQUARE), r(116, 60, SQUARE) })
    chartlayout.slots(sections)
    local built = chartlayout.build(sections, choices())
    local written = {}
    for _, col in ipairs(built.sections[1].treble) do
      for _, sp in ipairs(col) do written[#written + 1] = sp end
    end
    t:eq(table.concat(written, ","), "G9")
    t:eq(#built.warnings, 1)
    t:eq(built.warnings[1].type, "unwritable")
    t:eq(built.warnings[1].names[1], "G#8")
  end,
  shapes_pick_notehead_sets = function(t)
    local sections = sectionsOf({ r(72, 35, NORMAL), r(74, 36, DIAMOND) })
    chartlayout.slots(sections)
    local built = chartlayout.build(sections, choices({ shapes = { bells = "Square", chimes = MATCH } }))
    t:eq(built.sections[1].noteheadSet, SQUARE, "a chosen shape")
    t:eq(built.sections[2].noteheadSet, DIAMOND, "matching the music's notehead")
    t:eq(#built.warnings, 0)
  end,
  cone_has_no_set_and_warns_once = function(t)
    local sections = sectionsOf({ r(74, 36, DIAMOND), r(76, 37, DIAMOND) })
    chartlayout.slots(sections)
    local built = chartlayout.build(sections, choices({ shapes = { chimes = "Cone" } }))
    t:eq(built.sections[1].noteheadSet, nil)
    t:eq(#built.warnings, 1)
    t:eq(built.warnings[1].type, "missing-notehead")
    t:eq(built.warnings[1].instrument, "Handchimes")
    t:eq(built.warnings[1].names[1], "Cone")
  end,
  colours_are_canonical_and_bells_black = function(t)
    local sections = sectionsOf({ r(72, 35, NORMAL), r(74, 36, DIAMOND) })
    chartlayout.slots(sections)
    local built = chartlayout.build(sections, choices({ colours = { chimes = "C80000" } }))
    t:eq(built.sections[1].colour, "")
    t:eq(built.sections[2].colour, "#c80000")
  end,
  marker_sections_name_slot_keys = function(t)
    local sections = sectionsOf({ r(72, 35, NORMAL), r(84, 42, SQUARE) })
    chartlayout.slots(sections)
    local built = chartlayout.build(sections, choices())
    local ms = chartlayout.markerSections(built, { 7, 8 })
    t:eq(#ms, 2)
    t:eq(ms[1].kind .. "," .. ms[1].player .. "," .. ms[1].columns, "bells,7,1")
    t:eq(ms[2].kind .. "," .. ms[2].player .. "," .. ms[2].columns, "smbs,8,1")
  end,
  full_score_layout_holds_every_music_player = function(t)
    local layouts = { { id = 1, keys = { 0 } }, { id = 0, keys = { 0, 1, 2, 3 } }, { id = 5, keys = { 0, 1, 2 } } }
    t:eq(chartlayout.fullScoreLayout(layouts, { 0, 1, 2 }), 0)
    t:eq(chartlayout.fullScoreLayout({ { id = 1, keys = { 0 } } }, { 0, 1 }), nil)
  end,
  part_layouts_are_chart_only_layouts = function(t)
    local layouts = { { id = 0, keys = { 0, 1, 3, 4 } }, { id = 7, keys = { 3 } }, { id = 8, keys = { 4 } },
      { id = 2, keys = { 1 } }, { id = 9, keys = {} } }
    local ids = chartlayout.partLayouts(layouts, { 3, 4 }, 0)
    t:eq(#ids, 2)
    t:eq(ids[1], 7)
    t:eq(ids[2], 8)
  end,
  chart_headings_keep_later_flows_headings = function(t)
    -- One music flow: no heading, so its title isn't printed twice. Several: the chart is the first flow, so "after
    -- the first flow" hides only its heading.
    t:eq(chartlayout.chartHeadings("kAlwaysInsertHeadings", 1), "kNoFlowHeadings")
    t:eq(chartlayout.chartHeadings("kAddHeadingsAfterFirstFlow", 1), "kNoFlowHeadings")
    t:eq(chartlayout.chartHeadings("kAlwaysInsertHeadings", 3), "kAddHeadingsAfterFirstFlow")
    t:eq(chartlayout.chartHeadings("kAddHeadingsAfterFirstFlow", 3), "kAddHeadingsAfterFirstFlow",
      "later flows keep theirs")
    t:eq(chartlayout.chartHeadings("kNoFlowHeadings", 3), "kNoFlowHeadings")
  end,
  flow_breaks_follow_the_choice = function(t)
    t:eq(chartlayout.flowBreaks(true), "kStartNewPageForFlows")
    t:eq(chartlayout.flowBreaks(false), "kNoFlowBreaks")
  end,
}
