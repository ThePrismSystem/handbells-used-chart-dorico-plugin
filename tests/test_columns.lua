-- Ported from the Sibelius plugin's test/TestColumns.mss.
local columns = require("hbuc.columns")
local bellname = require("hbuc.bellname")

local function bell(pitch, diatonic, region)
  local b = bellname.nameOf(pitch, diatonic)
  b.region = region
  b.count = 1
  return b
end

local function pitchAt(cols, i, n)
  local col = cols[i]
  if not col then return -2 end
  local note = col[n]
  if not note then return -3 end
  return note.pitch
end

return {
  octave_stacks = function(t)
    local d6, d7, d8 = bell(86, 43, "trebleStaff"), bell(98, 50, "trebleRow1"), bell(110, 57, "trebleRow2")
    local a6, c3, c4 = bell(93, 47, "trebleStaff"), bell(48, 21, "bassRow1"), bell(60, 28, "bassStaff")
    local built = columns.build({ d6, d7, d8, a6, c3, c4 }, false)
    t:eq(#built.treble, 2, "two treble columns")
    t:eq(#built.bass, 2, "two bass columns")
    t:eq(#built.treble[1], 3, "D stacks three octaves")
    t:eq(pitchAt(built.treble, 1, 1), 86, "lowest in stack first")
    t:eq(pitchAt(built.treble, 1, 3), 110, "highest in stack last")
    t:eq(#built.treble[2], 1, "A6 is its own column")
    t:eq(pitchAt(built.bass, 1, 1), 48, "low bell leftmost")
    t:eq(pitchAt(built.bass, 2, 1), 60, "staff bell after it")
    t:eq(built.length, 2, "length is the wider side")
  end,
  single_staff = function(t)
    local c3, c5, d5 = bell(48, 21, "bassRow1"), bell(72, 35, "bassStaff"), bell(74, 36, "trebleStaff")
    local d6, d7 = bell(86, 43, "trebleStaff"), bell(98, 50, "trebleRow1")
    local built = columns.build({ c3, c5, d5, d6, d7 }, true)
    t:eq(#built.bass, 0, "a one-staff section writes no bass columns")
    t:eq(#built.treble, 4, "every bell reaches the treble staff")
    t:eq(pitchAt(built.treble, 2, 1), 72, "C5 is on the treble staff")
    t:eq(pitchAt(built.treble, 3, 1), 74, "D5 after it")
    t:eq(#built.treble[4], 2, "D6 and D7 still share a column")
    t:eq(pitchAt(built.treble, 4, 2), 98, "the octave above sits on top")
    t:eq(pitchAt(built.treble, 1, 1), 48, "a low bell sorts leftmost, not lost")
    t:eq(built.length, 4, "length is the treble side")
  end,
  orphan_sorts_by_absent_anchor = function(t)
    local built = columns.build({ bell(93, 47, "trebleStaff"), bell(103, 53, "trebleRow1") }, false)
    t:eq(#built.treble, 2, "orphan attachment makes its own column")
    t:eq(pitchAt(built.treble, 1, 1), 103, "orphan sorts by its absent anchor")
    t:eq(pitchAt(built.treble, 2, 1), 93, "staff bell sorts after it")
  end,
  enharmonic_columns_stay_apart = function(t)
    -- G#6 and Ab6 are one physical bell but two spellings: two columns, sharp first; G#7 joins G#6 only.
    local gs6, ab6, gs7 = bell(92, 46, "trebleStaff"), bell(92, 47, "trebleStaff"), bell(104, 53, "trebleRow1")
    local built = columns.build({ ab6, gs7, gs6 }, false)
    t:eq(#built.treble, 2)
    t:eq(built.treble[1][1].name, "G#6", "sharp column first")
    t:eq(#built.treble[1], 2, "G#7 stacks on G#6")
    t:eq(built.treble[2][1].name, "Ab6")
    t:eq(#built.treble[2], 1)
  end,
  empty_input = function(t)
    local built = columns.build({}, false)
    t:eq(#built.treble, 0)
    t:eq(#built.bass, 0)
    t:eq(built.length, 0)
  end,
  uses_one_staff = function(t)
    t:eq(columns.usesOneStaff("smbs"), true)
    t:eq(columns.usesOneStaff("bells"), false)
    t:eq(columns.usesOneStaff("chimes"), false)
  end,
}
