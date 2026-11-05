-- "Written as": an instrument written at pitch (a Piano or Organ staff) sounds as written, so its bells are an
-- octave above what Dorico stores; Dorico's Handbells instrument already stores the bell. A saved copy's score says
-- which instruments are which.
local build = require("dtn_build")
local dtn = require("hbuc.dtn")
local transpose = require("hbuc.transpose")
local zip = require("hbuc.zip")

local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"

local function rec(pitch, diatonic, instrument)
  return { pitch = pitch, diatonic = diatonic, head = "noteheadset.default", colour = "", instrument = instrument }
end

-- An instrument whose transposition node holds children ({name, value}...), is empty ({}), or is missing (nil).
local function instrument(id, transposition)
  local children = { { "instrumentID", tostring(id) } }
  if transposition then children[#children + 1] = { "transposition", nil, transposition } end
  return { "instrument", nil, children }
end

local function tree(...)
  local player = { "scorePlayer", nil, { { "playerID", "0" }, { "instruments", nil, { ... } } } }
  return dtn.decode(build.tree({ "kScore", nil, { { "scorePlayers", nil, { { "array", nil, { player } } } } } }))
end

local function keys(set)
  local out = {}
  for k, v in pairs(set) do if v then out[#out + 1] = k end end
  table.sort(out)
  return table.concat(out, " ")
end

return {
  -- The fixture's two Handbells players, and an Organ whose part is written at pitch.
  the_fixture_s_organ_is_written_at_pitch = function(t)
    local f = assert(io.open(here .. "../fixtures/handbells-fixture.dorico", "rb"))
    local bytes = f:read("*a")
    f:close()
    t:eq(keys(transpose.writtenAtPitch(dtn.decode(zip.entry(bytes, "score.dtn")))), "2")
  end,
  -- Dorico's Handbells is written an octave below its sound (fixedOctaveTransposition -1).
  an_instrument_written_an_octave_down_is_not = function(t)
    local octaveDown = { { "intervalForTransposingScores", "x" }, { "fixedOctaveTransposition", "-1" } }
    t:eq(keys(transpose.writtenAtPitch(tree(instrument(4, octaveDown), instrument(5, {}), instrument(6, nil),
      instrument(7, { { "fixedOctaveTransposition", "0" } })))), "5 6 7")
  end,
  no_players_none_at_pitch = function(t)
    t:eq(keys(transpose.writtenAtPitch(dtn.decode(build.tree({ "kScore", nil, {} })))), "")
  end,
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
