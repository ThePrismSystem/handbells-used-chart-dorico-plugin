-- "Written as": an instrument written at pitch (a Piano or Organ staff) sounds as written, so its bells are an
-- octave above what Dorico stores; Dorico's Handbells instrument already stores the bell.
local transpose = require("hbuc.transpose")

local function rec(pitch, diatonic, instrument)
  return { pitch = pitch, diatonic = diatonic, head = "noteheadset.default", colour = "", instrument = instrument }
end

return {
  at_pitch_instruments_rise_an_octave = function(t)
    local out = transpose.atPitch({ rec(53, 24, "Organ"), rec(72, 35, "Handbells") }, { "Organ" })
    t:eq(out[1].pitch, 65, "Organ's F3 becomes bell F4")
    t:eq(out[1].diatonic, 31)
    t:eq(out[1].instrument, "Organ")
    t:eq(out[1].head, "noteheadset.default", "everything else is kept")
    t:eq(out[2].pitch, 72, "a Handbells instrument is unchanged")
    t:eq(out[2].diatonic, 35)
  end,
  records_without_pitch_pass_through = function(t)
    local out = transpose.atPitch({ { instrument = "Organ", head = "", colour = "" } }, { "Organ" })
    t:eq(#out, 1)
    t:eq(out[1].pitch, nil)
  end,
  the_input_is_not_changed = function(t)
    local input = { rec(53, 24, "Organ") }
    transpose.atPitch(input, { "Organ" })
    t:eq(input[1].pitch, 53)
  end,
  at_pitch_bells_meet_the_range_check = function(t)
    -- the C2-C9 check sees the bell, not the written note: written B8 at pitch is bell B9, and written B1 is B2
    local NONE = require("hbuc.constants").NO_NOTEHEAD
    local plan = require("hbuc.plan")
    local records = transpose.atPitch({ rec(119, 62, "Organ"), rec(35, 13, "Organ"), rec(74, 36, "Organ") },
      { "Organ" })
    records[3].head = "noteheadset.diamondNoteheads"
    local p = plan.build(records, { instruments = { "Organ" }, mode = "combined", heads = {
      bells = "noteheadset.default", chimes = "noteheadset.diamondNoteheads", smbs = NONE, pf = NONE, whitechapel = NONE } })
    t:eq(#p.sections, 2)
    t:eq(p.sections[1].label, "Handbells Used: 1", "B2 is kept")
    t:eq(p.sections[2].label, "Handchimes Used: 1", "chimes move too")
    t:eq(#p.warnings, 1)
    t:eq(p.warnings[1].type, "out-of-range")
    t:eq(table.concat(p.warnings[1].names, " "), "B9", "B9 is past C9")
  end,
  no_names_changes_nothing = function(t)
    local out = transpose.atPitch({ rec(53, 24, "Organ") }, {})
    t:eq(out[1].pitch, 53)
    t:eq(#transpose.atPitch({}, { "Organ" }), 0)
  end,
}
