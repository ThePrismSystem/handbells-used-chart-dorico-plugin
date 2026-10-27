-- Ported from the Sibelius plugin's test/TestOptions.mss and test/TestNoteHeads.mss (the cases that need no
-- score), plus the colour-garbage and settings cases this plugin adds.
local options = require("hbuc.options")
local constants = require("hbuc.constants")
local report = require("hbuc.report")

local NONE = constants.NO_NOTEHEAD
local join = report.joinNames

local function heads(b, c, s, p, w) return { bells = b, chimes = c, smbs = s, pf = p, whitechapel = w } end

return {
  trim = function(t)
    t:eq(options.trim(""), "")
    t:eq(options.trim("   "), "")
    t:eq(options.trim("abc"), "abc")
    t:eq(options.trim("  abc"), "abc")
    t:eq(options.trim("abc  "), "abc")
    t:eq(options.trim("  abc  "), "abc")
    t:eq(options.trim("a b"), "a b")
    t:eq(options.trim(" a b "), "a b")
    t:eq(options.trim(0), "0", "trim coerces a number")
  end,
  usable_colour = function(t)
    t:eq(options.usableColour(""), "")
    t:eq(options.usableColour("   "), "")
    t:eq(options.usableColour("c00000"), "#c00000", "a bare hex value gains its hash")
    t:eq(options.usableColour("#c00000"), "#c00000")
    t:eq(options.usableColour(" #c00000 "), "#c00000")
    t:eq(options.usableColour(" c00000 "), "#c00000")
    t:eq(options.usableColour("c000"), "", "a short value is refused")
    t:eq(options.usableColour("#c000000"), "", "a long value is refused")
    t:eq(options.usableColour("#"), "", "a lone hash is refused")
  end,
  usable_colour_matches_sibelius = function(t)
    t:eq(options.usableColour(" #C00000 "), "#C00000", "case kept")
    t:eq(options.usableColour("c00000"), "#c00000")
    t:eq(options.usableColour("#12345"), "")
    t:eq(options.usableColour("zz0000"), "#zz0000", "passes the length rule")
    t:eq(options.usableColour(""), "")
  end,
  canonical_colour = function(t)
    -- HexDigit/HexByte's rules, written back as the #rrggbb Dorico's kEventColour takes.
    t:eq(options.canonicalColour("#FF0000"), "#ff0000", "upper case reads the same")
    t:eq(options.canonicalColour("#66FF00"), "#66ff00")
    t:eq(options.canonicalColour("#zz0000"), "#000000", "a non-digit reads as zero")
    t:eq(options.canonicalColour(""), "", "no colour stays no colour")
  end,
  duplicate_head = function(t)
    t:eq(options.duplicateHead(heads("Normal", "Diamond", "Square", NONE, NONE)), "", "three different heads are fine")
    t:eq(options.duplicateHead(heads("Normal", "Normal", "Square", NONE, NONE)), "Normal", "bells and chimes")
    t:eq(options.duplicateHead(heads("Normal", "Diamond", "Normal", NONE, NONE)), "Normal", "bells and SMBs")
    t:eq(options.duplicateHead(heads("Normal", "Diamond", "Diamond", NONE, NONE)), "Diamond", "chimes and SMBs")
    t:eq(options.duplicateHead(heads("Normal", "Diamond", "Square", "Normal", NONE)), "Normal", "bells and P&F")
    t:eq(options.duplicateHead(heads("Normal", "Diamond", "Square", "Cross", "Cross")), "Cross", "P&F and Whitechapel")
    t:eq(options.duplicateHead(heads("Normal", "Diamond", "Square", "Cross", "Slashed")), "", "five different heads")
    t:eq(options.duplicateHead(heads("Normal", NONE, NONE, NONE, NONE)), "", "no-notehead may repeat")
    t:eq(options.duplicateHead(heads(NONE, NONE, NONE, NONE, NONE)), "", "nothing chosen is not a clash")
  end,
  section_colour = function(t)
    local colours = { chimes = "#111111", smbs = "#222222", pf = "#333333", whitechapel = "#444444" }
    t:eq(options.sectionColour("pf", colours), "#333333", "P&F bells take their own colour")
    t:eq(options.sectionColour("whitechapel", colours), "#444444")
    t:eq(options.sectionColour("bells", colours), "", "handbells stay black")
  end,
  pipe_lists = function(t)
    t:eq(#options.pipeList(""), 0, "an empty memory is no names")
    t:eq(join(options.pipeList("Piano|Flute")), "Piano, Flute", "memory splits on the pipe")
    t:eq(options.joinPipe({ "Piano", "Flute" }), "Piano|Flute", "memory joins on the pipe")
    t:eq(options.joinPipe({}), "", "no names joins to nothing")
    local escaped = options.joinPipe({ "Bells A|B", "Bells ~5" })
    t:eq(escaped, "Bells A~pB|Bells ~~5", "a pipe or tilde in a name is escaped")
    local back = options.pipeList(escaped)
    t:eq(#back, 2, "an escaped pipe does not split the name")
    t:eq(join(back), "Bells A|B, Bells ~5", "escaped names read back as they were")
  end,
  pipe_list_round_trips_awkward_names = function(t)
    local names = { "A|B", "C~D", 'E"F', "" }
    local back = options.pipeList(options.joinPipe(names))
    t:eq(#back, 4)
    for i = 1, 4 do t:eq(back[i], names[i], "name " .. i) end
  end,
  preselected_and_excluded = function(t)
    local offered = { "Handbells I", "Handbells II", "Piano" }
    t:eq(join(options.preselected(offered, {})), "Handbells I, Handbells II, Piano", "a first run selects everything")
    t:eq(join(options.preselected(offered, { "Piano", "Flute" })), "Handbells I, Handbells II")
    t:eq(join(options.preselected({ "Bells A" }, { "Handbells I" })), "Bells A", "a renamed instrument is new")
    t:eq(join(options.excludedAfterRun({}, offered, { "Handbells I", "Handbells II" })), "Piano")
    t:eq(join(options.excludedAfterRun({ "Piano", "Flute" }, offered, offered)), "Flute")
    t:eq(join(options.excludedAfterRun({ "Flute" }, offered, { "Piano" })), "Flute, Handbells I, Handbells II")
    t:eq(join(options.excludedAfterRun({ "Flute" }, offered, {})), "Flute", "nothing selected changes nothing")
  end,
  chart_mode = function(t)
    t:eq(options.chartModeOf(constants.CHART_MODE_SEPARATE), "separate")
    t:eq(options.chartModeOf(constants.CHART_MODE_COMBINED), "combined")
    t:eq(options.chartModeOf(""), "combined")
    t:eq(options.chartModeOf("something else"), "combined")
  end,
  preferred_head = function(t)
    local names = { "Normal", "Diamond", "Cross" }
    t:eq(options.preferredHead(names, "Cross", "Normal"), "Cross", "a remembered head the score still uses wins")
    t:eq(options.preferredHead(names, "Slashed", "Normal"), "Normal", "an unusable remembered head falls back")
    t:eq(options.preferredHead(names, "", "Diamond"), "Diamond")
    t:eq(options.preferredHead({ "Normal" }, "", "Diamond"), NONE, "a missing fallback opens on no notehead")
    t:eq(options.preferredHead({}, "", "Diamond"), NONE)
    t:eq(options.preferredHead(names, NONE, "Diamond"), "Diamond", "no-notehead is not itself a remembered head")
  end,
  head_choice_items = function(t)
    local items = options.headChoiceItems({ "Normal", "Diamond", "Cross" })
    t:eq(#items, 4)
    t:eq(items[1], NONE, "the no-notehead entry comes first")
    t:eq(items[2], "Normal", "the score heads follow in the order found")
    t:eq(#options.headChoiceItems({}), 1)
  end,
  head_colours = function(t)
    local tally = {}
    t:eq(options.mostUsedColour(tally, "Diamond"), "", "a head no note carries has no colour")
    options.tallyColour(tally, "Diamond", "#c00000")
    options.tallyColour(tally, "Diamond", "")
    options.tallyColour(tally, "Diamond", "#c00000")
    options.tallyColour(tally, "Cross", "")
    options.tallyColour(tally, "Cross", "")
    options.tallyColour(tally, "Cross", "#00ff00")
    options.tallyColour(tally, "Square", "#00ff00")
    options.tallyColour(tally, "Square", "#0000ff")
    t:eq(options.mostUsedColour(tally, "Diamond"), "#c00000", "the colour most of the notes carry")
    t:eq(options.mostUsedColour(tally, "Cross"), "", "a head mostly black has no colour")
    t:eq(options.mostUsedColour(tally, "Square"), "#00ff00", "a tie goes to the colour found first")
    t:eq(options.mostUsedColour(tally, NONE), "")
    t:eq(options.openingColour("#123456", tally, "Diamond"), "#123456", "a remembered colour is kept")
    t:eq(options.openingColour("  ", tally, "Diamond"), "#c00000", "a blank field opens on its notehead's colour")
    t:eq(options.openingColour("", tally, "Cross"), "")
  end,
  settings_round_trip = function(t)
    local s = { excluded = "Piano|Organ", mode = "separate",
      heads = { bells = "noteheadset.default", chimes = "noteheadset.diamondNoteheads" },
      shapes = { chimes = "Square" }, colours = { chimes = "#c80000" } }
    local back = options.decodeSettings(options.encodeSettings(s))
    t:eq(back.excluded, "Piano|Organ")
    t:eq(back.mode, "separate")
    t:eq(back.heads.chimes, "noteheadset.diamondNoteheads")
    t:eq(back.heads.smbs, "", "missing kinds default to empty")
    t:eq(back.shapes.chimes, "Square")
    t:eq(back.colours.chimes, "#c80000")
  end,
  corrupt_settings_give_defaults = function(t)
    for _, text in ipairs({ "{bad", "", "[]", '{"mode": 3}' }) do
      local d = options.decodeSettings(text)
      t:eq(d.mode, "combined", "mode default for " .. text)
      t:eq(d.excluded, "", "excluded default for " .. text)
      t:eq(d.heads.bells, "", "heads default for " .. text)
    end
    t:eq(options.decodeSettings(nil).mode, "combined")
  end,
  at_pitch_after_run_keeps_names_not_offered = function(t)
    local after = options.atPitchAfterRun({ "Old", "Organ" }, { "Organ", "A" }, { "A" })
    t:eq(join(after), "Old, A", "Old is not offered and stays; Organ was offered and unset; A was set")
    t:eq(#options.atPitchAfterRun({}, { "A" }, {}), 0)
  end,
  at_pitch_names_round_trip_awkward_characters = function(t)
    local names = { 'P|F ~ "x"', "Organ" }
    local text = options.encodeSettings({ atPitch = options.joinPipe(names) })
    local back = options.pipeList(options.decodeSettings(text).atPitch)
    t:eq(#back, 2)
    t:eq(back[1], 'P|F ~ "x"')
    t:eq(back[2], "Organ")
    t:eq(options.decodeSettings("").atPitch, "", "nothing remembered")
  end,
  duplicate_head_names_the_first_instrument_with_a_twin = function(t)
    -- As the Sibelius plugin's DuplicateHead: the earliest instrument that a later one repeats, not the first repeat.
    t:eq(options.duplicateHead(heads("Normal", "Diamond", "Diamond", "Normal", NONE)), "Normal")
  end,
}
