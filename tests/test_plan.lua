-- Ported from the Sibelius plugin's test/TestPlan.mss. Records carry their instrument's name instead of a
-- staff number: in Dorico the stream map gives each voice stream's instrument.
local plan = require("hbuc.plan")
local constants = require("hbuc.constants")
local report = require("hbuc.report")

local NONE = constants.NO_NOTEHEAD
local NORMAL, DIAMOND, CROSS = "noteheadset.default", "noteheadset.diamondNoteheads", "noteheadset.Xnoteheads"
local SLASHED, SQUARE = "noteheadset.slashNoteheads", "noteheadset.rectangular"

local function r(pitch, diatonic, head, instrument)
  return { pitch = pitch, diatonic = diatonic, head = head, colour = "", instrument = instrument or "I" }
end
local function heads(b, c, s, p, w) return { bells = b, chimes = c, smbs = s, pf = p, whitechapel = w } end

local basic = { r(72, 35, NORMAL), r(80, 39, NORMAL), r(80, 40, NORMAL), r(74, 36, DIAMOND), r(74, 36, CROSS) }

return {
  sections_and_labels = function(t)
    local p = plan.buildOne(basic, heads(NORMAL, DIAMOND, NONE, NONE, NONE))
    t:eq(#p.sections, 2, "bells and chimes sections")
    t:eq(p.sections[1].kind, "bells", "bells first")
    t:eq(p.sections[1].label, "Handbells Used: 2", "bell label counts pitches")
    t:eq(p.sections[2].label, "Handchimes Used: 1", "chime label")
    t:eq(#p.warnings, 1, "one warning")
    t:eq(p.warnings[1].type, "unknown-notehead", "warning type")
  end,
  smbs_third_on_one_staff = function(t)
    local p = plan.buildOne(basic, heads(NORMAL, DIAMOND, CROSS, NONE, NONE))
    t:eq(#p.sections, 3, "three sections")
    t:eq(p.sections[3].kind, "smbs", "SMBs come last")
    t:eq(p.sections[3].label, "SMBs Used: 1", "SMB label")
    t:eq(#p.sections[3].bass, 0, "the SMB section writes no bass columns")
    t:eq(#p.sections[3].treble, 1, "the SMB bell is on the treble staff")
    t:eq(#p.warnings, 0, "nothing unrecognised once every head is chosen")
  end,
  kind_names = function(t)
    t:eq(plan.kindName("bells"), "Handbells")
    t:eq(plan.kindName("chimes"), "Handchimes")
    t:eq(plan.kindName("smbs"), "SMBs")
    t:eq(plan.kindName("pf"), "P&F Handbells")
    t:eq(plan.kindName("whitechapel"), "Whitechapel Handbells")
  end,
  makers_follow_smbs = function(t)
    local makers = { r(79, 39, NORMAL), r(72, 35, SQUARE), r(74, 36, SLASHED), r(76, 37, SLASHED), r(77, 38, CROSS) }
    local p = plan.buildOne(makers, heads(NORMAL, DIAMOND, CROSS, SLASHED, SQUARE))
    t:eq(#p.sections, 4, "bells, SMBs, P&F and Whitechapel sections")
    t:eq(p.sections[3].kind, "pf", "P&F bells follow the SMBs")
    t:eq(p.sections[3].label, "P&F Handbells Used: 2", "P&F label")
    t:eq(p.sections[4].kind, "whitechapel", "Whitechapel bells come last")
    t:eq(p.sections[4].label, "Whitechapel Handbells Used: 1", "Whitechapel label")
    t:eq(#p.sections[4].bass, 1, "a Whitechapel C5 sits on the bass staff")
    t:eq(#p.sections[4].treble, 0, "as a handbell C5 does")
  end,
  no_notes_no_sections = function(t)
    t:eq(#plan.buildOne({}, heads(NORMAL, DIAMOND, NONE, NONE, NONE)).sections, 0)
  end,
  separate_and_combined = function(t)
    local records = { r(72, 35, NORMAL, "Handbells I"), r(74, 36, DIAMOND, "Handbells I"), r(72, 35, NORMAL, "Handbells II"),
      r(76, 37, NORMAL, "Handbells II"), r(77, 38, CROSS, "Handbells II") }
    local instruments = { "Handbells I", "Handbells II", "Piano" }
    local h = heads(NORMAL, DIAMOND, NONE, NONE, NONE)
    local separate = plan.build(records, { heads = h, instruments = instruments, mode = "separate" })
    t:eq(#separate.sections, 3, "two sections for the first choir, one for the second")
    t:eq(separate.sections[1].label, "Handbells I - Handbells Used: 1", "full score label names the instrument")
    t:eq(separate.sections[1].plainLabel, "Handbells Used: 1", "plain label is the label as today")
    t:eq(report.joinNames(separate.sections[1].owners), "Handbells I", "a separate section has one owner")
    t:eq(separate.sections[2].label, "Handbells I - Handchimes Used: 1", "chimes follow bells within an instrument")
    t:eq(separate.sections[3].label, "Handbells II - Handbells Used: 2", "second instrument after the first")
    t:eq(report.joinNames(separate.emptyNames), "Piano", "an instrument with nothing to chart is named")
    t:eq(#separate.warnings, 1, "warnings are reported once for the run")
    t:eq(separate.warnings[1].type, "unknown-notehead", "the unrecognised head is still reported")

    local combined = plan.build(records, { heads = h, instruments = instruments, mode = "combined" })
    t:eq(#combined.sections, 2, "combined pools every instrument")
    t:eq(combined.sections[1].label, "Handbells Used: 2", "combined labels are unchanged")
    t:eq(combined.sections[1].plainLabel, combined.sections[1].label, "combined plain label is the label")
    t:eq(report.joinNames(combined.sections[1].owners), "Handbells I, Handbells II, Piano",
      "combined sections belong to every selected instrument")
    t:eq(#combined.emptyNames, 0, "combined names no empty instruments")

    local one = plan.build(records, { heads = h, instruments = { "Handbells I" }, mode = "separate" })
    t:eq(one.sections[1].label, "Handbells Used: 1", "one instrument is never prefixed")

    local narrowed = plan.build({ records[1] }, { heads = h, instruments = { "Handbells I", "Handbells II" }, mode = "separate" })
    t:eq(report.joinNames(narrowed.emptyNames), "Handbells II", "an instrument with no notes is named")
  end,
  unselected_instruments_are_not_charted = function(t)
    local records = { r(72, 35, NORMAL, "Handbells"), r(60, 28, NORMAL, "Organ") }
    local p = plan.build(records, { heads = heads(NORMAL, NONE, NONE, NONE, NONE), instruments = { "Handbells" }, mode = "combined" })
    t:eq(p.sections[1].label, "Handbells Used: 1", "the organ's plain notes are left out")
  end,
  nothing_in_range_still_warns = function(t)
    local p = plan.build({ r(35, 13, NORMAL), r(122, 64, NORMAL) },
      { heads = heads(NORMAL, NONE, NONE, NONE, NONE), instruments = { "I" }, mode = "combined" })
    t:eq(#p.sections, 0)
    t:eq(#p.warnings, 1)
    t:eq(p.warnings[1].type, "out-of-range")
    t:eq(report.joinNames(p.warnings[1].names), "B1, D9")
  end,
  no_instruments_no_sections = function(t)
    local p = plan.build(basic, { heads = heads(NORMAL, DIAMOND, NONE, NONE, NONE), instruments = {}, mode = "combined" })
    t:eq(#p.sections, 0)
    t:eq(#p.warnings, 0)
  end,
  no_heads_charts_nothing = function(t)
    local p = plan.build(basic, { instruments = { "I" }, mode = "combined" })
    t:eq(#p.sections, 0)
  end,
}
