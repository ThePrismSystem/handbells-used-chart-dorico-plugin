-- Ported from the Sibelius plugin's test/TestCollect.mss, with Dorico notehead set ids in place of
-- Sibelius NoteStyleName values (Normal, Diamond, Cross, Slashed, Square).
local collect = require("hbuc.collect")
local constants = require("hbuc.constants")

local NONE = constants.NO_NOTEHEAD
local NORMAL = "noteheadset.default"
local DIAMOND = "noteheadset.diamondNoteheads"
local CROSS = "noteheadset.Xnoteheads"
local SLASHED = "noteheadset.slashNoteheads"
local SQUARE = "noteheadset.rectangular"

local function r(pitch, diatonic, head) return { pitch = pitch, diatonic = diatonic, head = head, colour = "", instrument = "I" } end
local function heads(b, c, s, p, w) return { bells = b, chimes = c, smbs = s, pf = p, whitechapel = w } end

return {
  collects_sorts_counts_and_warns = function(t)
    local records = { r(80, 39, NORMAL), r(72, 35, NORMAL), r(80, 40, NORMAL), r(72, 35, NORMAL), r(74, 36, DIAMOND),
      r(74, 36, CROSS), r(12, 0, NORMAL) }
    local got = collect.bells(records, heads(NORMAL, DIAMOND, NONE, NONE, NONE))
    t:eq(#got.bells, 3, "three distinct bells")
    t:eq(got.bells[1].name, "C5", "lowest bell first")
    t:eq(got.bells[1].count, 2, "repeated bell counted twice")
    t:eq(got.bells[2].name, "G#5", "sharp spelling before flat")
    t:eq(got.bells[3].name, "Ab5", "flat spelling after sharp")
    t:eq(#got.chimes, 1, "one chime")
    t:eq(got.chimes[1].name, "D5", "chime name")
    t:eq(got.unknown, 1, "unrecognised notehead counted")
    t:eq(#got.unknownNames, 1, "the unrecognised head is named")
    t:eq(got.unknownNames[1], CROSS, "the unrecognised head name")
    t:eq(#got.outOfRange, 1, "out of range recorded")
    t:eq(got.outOfRange[1], "C0", "out of range name")
  end,
  chosen_heads_decide_the_kind = function(t)
    local custom = { r(72, 35, NORMAL), r(74, 36, CROSS) }
    local chosen = collect.bells(custom, heads(NORMAL, CROSS, NONE, NONE, NONE))
    t:eq(#chosen.chimes, 1, "a chosen chime head is charted as chimes")
    t:eq(chosen.chimes[1].name, "D5", "chosen chime head name")
    t:eq(chosen.unknown, 0, "a chosen chime head is not unrecognised")
    local swapped = collect.bells(custom, heads(CROSS, DIAMOND, NONE, NONE, NONE))
    t:eq(#swapped.bells, 1, "a chosen bell head is charted as bells")
    t:eq(swapped.bells[1].name, "D5", "chosen bell head name")
    t:eq(swapped.unknown, 1, "the unchosen head is now unrecognised")
    t:eq(swapped.unknownNames[1], NORMAL, "the unchosen head is named")
    local bellsOnly = collect.bells(custom, heads(NORMAL, NONE, NONE, NONE, NONE))
    t:eq(#bellsOnly.bells, 1, "no notehead chosen for chimes still charts bells")
    t:eq(#bellsOnly.chimes, 0, "no notehead chosen for chimes charts no chimes")
    t:eq(#bellsOnly.smbs, 0, "no notehead chosen for SMBs charts no SMBs")
    t:eq(#bellsOnly.pf, 0, "no notehead chosen for P&F bells charts none")
    t:eq(#bellsOnly.whitechapel, 0, "no notehead chosen for Whitechapel bells charts none")
  end,
  unknown_heads_named_once = function(t)
    local twice = collect.bells({ r(72, 35, CROSS), r(74, 36, CROSS), r(76, 37, SLASHED) },
      heads(NORMAL, DIAMOND, NONE, NONE, NONE))
    t:eq(twice.unknown, 3, "every unrecognised note is counted")
    t:eq(#twice.unknownNames, 2, "each unrecognised head is named once")
  end,
  empty_choice_matches_nothing = function(t)
    local none = collect.bells({ r(72, 35, "") }, heads("", "", "", "", ""))
    t:eq(#none.bells, 0, "an empty bell choice matches nothing")
    t:eq(#none.chimes, 0, "an empty chime choice matches nothing")
    t:eq(none.unknown, 1, "an unmatched note is counted as unrecognised")
    t:eq(#none.unknownNames, 0, "an unnamed head contributes no name")
  end,
  three_instruments = function(t)
    local all3 = collect.bells({ r(72, 35, NORMAL), r(74, 36, DIAMOND), r(79, 39, CROSS), r(76, 37, CROSS) },
      heads(NORMAL, DIAMOND, CROSS, NONE, NONE))
    t:eq(#all3.bells, 1, "bells alongside two other instruments")
    t:eq(#all3.chimes, 1, "chimes alongside two other instruments")
    t:eq(#all3.smbs, 2, "two distinct SMBs")
    t:eq(all3.smbs[1].name, "E5", "SMBs sort by pitch like the rest")
    t:eq(all3.smbs[2].name, "G5", "SMBs sort by pitch like the rest")
    t:eq(all3.unknown, 0, "a third chosen head leaves nothing unrecognised")
  end,
  five_instruments = function(t)
    local all5 = collect.bells({ r(72, 35, NORMAL), r(76, 37, SLASHED), r(74, 36, SLASHED), r(74, 36, SLASHED),
      r(79, 39, SQUARE) }, heads(NORMAL, DIAMOND, CROSS, SLASHED, SQUARE))
    t:eq(#all5.bells, 1, "bells alongside the bells of two makers")
    t:eq(#all5.pf, 2, "two distinct P&F bells")
    t:eq(all5.pf[1].name, "D5", "P&F bells sort by pitch like the rest")
    t:eq(all5.pf[1].count, 2, "a repeated P&F bell is counted twice")
    t:eq(all5.pf[2].name, "E5", "P&F bells sort by pitch like the rest")
    t:eq(#all5.whitechapel, 1, "one Whitechapel bell")
    t:eq(all5.whitechapel[1].name, "G5", "the Whitechapel bell name")
    t:eq(all5.unknown, 0, "five chosen heads leave nothing unrecognised")
  end,
  unreadable_pitches_counted = function(t)
    local got = collect.bells({ { pitch = nil, diatonic = 35, head = NORMAL }, { pitch = 72, diatonic = "x", head = NORMAL },
      r(72, 35, NORMAL) }, heads(NORMAL, NONE, NONE, NONE, NONE))
    t:eq(got.unreadable, 2)
    t:eq(#got.bells, 1)
  end,
  enharmonics_are_two_entries = function(t)
    local got = collect.bells({ r(80, 40, NORMAL), r(80, 39, NORMAL) }, heads(NORMAL, NONE, NONE, NONE, NONE))
    t:eq(#got.bells, 2)
    t:eq(got.bells[1].name, "G#5", "sharp first")
    t:eq(got.bells[2].name, "Ab5")
  end,
  double_sharp_sorts_before_sharp = function(t)
    -- Fx5 and G5 share pitch 79: double sharp through double flat, as published charts print them.
    local got = collect.bells({ r(79, 39, NORMAL), r(79, 38, NORMAL), r(79, 40, NORMAL) }, heads(NORMAL, NONE, NONE, NONE, NONE))
    t:eq(got.bells[1].name, "Fx5")
    t:eq(got.bells[2].name, "G5")
    t:eq(got.bells[3].name, "Abb5")
  end,
  out_of_range_named_once = function(t)
    local got = collect.bells({ r(35, 13, NORMAL), r(35, 13, NORMAL) }, heads(NORMAL, NONE, NONE, NONE, NONE))
    t:eq(#got.outOfRange, 1)
    t:eq(got.outOfRange[1], "B1")
  end,
  entries_carry_region = function(t)
    local got = collect.bells({ r(72, 35, NORMAL) }, heads(NORMAL, NONE, NONE, NONE, NONE))
    t:eq(got.bells[1].region, "bassStaff")
  end,
  odd_numbers_are_unreadable = function(t)
    local got = collect.bells({ r(60.5, 28, NORMAL), r(0 / 0, 28, NORMAL), r(60, math.huge, NORMAL), r(60, 28.5, NORMAL),
      r(72, 35, NORMAL) }, heads(NORMAL, NONE, NONE, NONE, NONE))
    t:eq(got.unreadable, 4, "a fractional, NaN or infinite pitch or index is unreadable")
    t:eq(#got.bells, 1, "the good note is still charted")
  end,
  no_heads_match_nothing = function(t)
    local got = collect.bells({ r(72, 35, NORMAL) }, nil)
    t:eq(got.unknown, 1, "with no heads chosen, every note is unrecognised")
  end,
}
