-- Chart players (slots), reuse on update, and what each section writes where.
local build = require("dtn_build")
local chartlayout = require("hbuc.chartlayout")
local dtn = require("hbuc.dtn")
local plan = require("hbuc.plan")
local constants = require("hbuc.constants")
local zip = require("hbuc.zip")

local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"

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

-- Pages as the saved copies of Steinberg's Liszt example and the fixture give them, in staff spaces.
local LISZT = { frame = (648 - 2 * 42.5197) / 4.61, crotchet = 27 / 8, indent = 6 }
local FIXTURE = { frame = (612 - 84) / 4.96, crotchet = 4, indent = 0 }

-- A built chart with sections of these column counts, all naturals.
local function chart(...)
  local sections = {}
  for i, columns in ipairs({ ... }) do sections[i] = { columns = columns, treble = {}, bass = {} } end
  return { sections = sections }
end

-- One section of n columns, each holding this spelling on this staff.
local function spelled(n, staff, spelling)
  local built = chart(n)
  for c = 1, n do built.sections[1][staff][c] = { spelling } end
  return built
end

-- A score tree with one layout. over: a layoutOptions value to leave out or replace, by name.
local function layoutTree(id, over)
  over = over or {}
  local function value(name, default)
    local v = over[name]
    if v == false then return nil end
    return v or default
  end
  local function leaf(list, name, default)
    local v = value(name, default)
    if v then list[#list + 1] = { name, v, {} } end
  end
  local margins = {}
  leaf(margins, "outer", "40")
  leaf(margins, "inner", "20")
  local page = { { "margins", nil, { { "margins", nil, margins } } } }
  leaf(page, "pageWidth", "600")
  local spacing = {}
  leaf(spacing, "crotchetSize", "7/2")
  local options = { { "pageSizeAndMarginOptions", nil, page }, { "noteSpacingOptions", nil, spacing } }
  leaf(options, "defaultSpaceSize", "5")
  leaf(options, "flowFirstSystemIndent", "6")
  local layout = { "layout", nil, { { "layoutID", tostring(id), {} }, { "layoutOptions", nil, options } } }
  return dtn.decode(build.tree({ "kScore", nil, { { "layouts", nil, { { "array", nil, { layout } } } } } }))
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
  the_last_section_is_spread = function(t)
    local sections = sectionsOf({ r(74, 36, NORMAL), r(76, 37, NORMAL), r(74, 36, DIAMOND), r(76, 37, DIAMOND) })
    chartlayout.slots(sections)
    local built = chartlayout.build(sections, choices())
    t:eq(built.sections[1].step, 1)
    t:eq(built.sections[2].step, chartlayout.LAST_STEP)
    t:eq(built.sections[2].start, 2, "it starts where the section before it ends")
    t:eq(chartlayout.LAST_STEP > 1, true)
  end,
  a_chart_of_one_section_is_spread = function(t)
    local sections = sectionsOf({ r(74, 36, NORMAL) })
    chartlayout.slots(sections)
    t:eq(chartlayout.build(sections, choices()).sections[1].step, chartlayout.LAST_STEP)
  end,
  length_takes_in_the_spread_section_and_its_end_note = function(t)
    local step = chartlayout.LAST_STEP
    t:eq(chartlayout.length({ { columns = 3 }, { columns = 2 } }), 3 + 2 * step + 1)
    t:eq(chartlayout.length({ { columns = 4 } }), 4 * step + 1)
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
  a_chart_that_fits_stays_full_size = function(t)
    t:eq(chartlayout.staffPercent(chart(20), FIXTURE), 100)
    t:eq(chartlayout.staffPercent(chart(), FIXTURE), 100)
  end,
  a_page_that_could_not_be_read_leaves_the_size_alone = function(t)
    t:eq(chartlayout.staffPercent(chart(90), nil), 100)
  end,
  -- Liszt's chart spilled at 70% and fitted at 60%.
  a_wide_chart_shrinks_to_fit = function(t)
    t:eq(chartlayout.staffPercent(chart(48), LISZT), 65)
    t:eq(chartlayout.staffPercent(chart(45), LISZT), 70, "fewer columns, less shrinking")
  end,
  the_page_sets_how_many_columns_fit = function(t)
    t:eq(chartlayout.staffPercent(chart(30), FIXTURE), 75)
    t:eq(chartlayout.staffPercent(chart(30), { frame = FIXTURE.frame, crotchet = 3, indent = 0 }), 100,
      "tighter note spacing")
    t:eq(chartlayout.staffPercent(chart(30), { frame = 155, crotchet = 4, indent = 0 }), 100, "a smaller space size")
  end,
  only_the_last_section_has_an_end_note = function(t)
    t:eq(chartlayout.staffPercent(chart(23), FIXTURE), 95, "23 columns and the end note")
    t:eq(chartlayout.staffPercent(chart(23, 5), FIXTURE), 100, "23 columns alone")
  end,
  only_the_first_section_is_indented = function(t)
    t:eq(chartlayout.staffPercent(chart(31), LISZT), 95, "on the flow's first system")
    t:eq(chartlayout.staffPercent(chart(5, 31), LISZT), 100, "on a later one")
  end,
  the_widest_section_decides = function(t)
    t:eq(chartlayout.staffPercent(chart(5, 30), FIXTURE), 75, "last, with the end note")
    t:eq(chartlayout.staffPercent(chart(30, 5), FIXTURE), 80, "first")
  end,
  -- With a crotchet's space of 5/2, 32 columns of sharps and flats fitted where the spacing alone would hold 41.
  accidentals_widen_columns_only_in_tight_spacing = function(t)
    local tight = { frame = FIXTURE.frame, crotchet = 5 / 2, indent = 0 }
    t:eq(chartlayout.staffPercent(chart(40), tight), 90, "naturals")
    t:eq(chartlayout.staffPercent(spelled(40, "treble", "C#5"), tight), 70, "sharps")
    t:eq(chartlayout.staffPercent(spelled(40, "bass", "Db3"), tight), 70, "flats, on the other staff")
    t:eq(chartlayout.staffPercent(spelled(40, "treble", "Fx5"), tight), 70, "double sharps")
    t:eq(chartlayout.staffPercent(spelled(40, "treble", "B5"), tight), 90, "B is a letter, not a flat")
    t:eq(chartlayout.staffPercent(spelled(30, "treble", "C#5"), FIXTURE), 75, "the usual spacing holds them")
  end,
  a_column_counts_once_with_accidentals_on_both_staves = function(t)
    local tight = { frame = FIXTURE.frame, crotchet = 5 / 2, indent = 0 }
    local built = spelled(40, "treble", "C#5")
    for c = 1, 40 do built.sections[1].bass[c] = { "Db3" } end
    t:eq(chartlayout.staffPercent(built, tight), 70)
  end,
  a_chart_too_wide_even_small_stops_shrinking = function(t)
    t:eq(chartlayout.staffPercent(chart(90), FIXTURE), chartlayout.MIN_PERCENT)
  end,
  pages_read_from_the_fixture = function(t)
    local f = assert(io.open(here .. "../fixtures/handbells-fixture.dorico", "rb"))
    local bytes = f:read("*a")
    f:close()
    local page = chartlayout.pages(dtn.decode(zip.entry(bytes, "score.dtn")))[0]
    t:eq(page.frame, FIXTURE.frame)
    t:eq(page.crotchet, 4)
    t:eq(page.indent, 0)
  end,
  page_values_can_be_fractions = function(t)
    local page = chartlayout.pages(layoutTree(3))[3]
    t:eq(page.frame, 108, "(600 - 40 - 20) / 5")
    t:eq(page.crotchet, 3.5)
    t:eq(page.indent, 6)
  end,
  a_missing_indent_is_none = function(t)
    t:eq(chartlayout.pages(layoutTree(3, { flowFirstSystemIndent = false }))[3].indent, 0)
  end,
  a_layout_missing_a_size_has_no_page = function(t)
    for _, name in ipairs({ "pageWidth", "defaultSpaceSize", "crotchetSize", "outer", "inner" }) do
      t:eq(chartlayout.pages(layoutTree(3, { [name] = false }))[3], nil, name)
    end
  end,
  a_score_with_no_layouts_has_no_pages = function(t)
    t:eq(next(chartlayout.pages(dtn.decode(build.tree({ "kScore", nil, {} })))), nil)
  end,
}
