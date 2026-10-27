-- The name-related cases of the Sibelius plugin's test/TestInstruments.mss.
local instruments = require("hbuc.instruments")
local report = require("hbuc.report")

local function r(instrument, pitch) return { pitch = pitch, diatonic = 35, head = "h", colour = "", instrument = instrument } end

return {
  twins_are_told_apart = function(t)
    t:eq(report.joinNames(instruments.unique({ "Handbells", "Handbells", "Handbells" })),
      "Handbells, Handbells (2), Handbells (3)", "instruments sharing a name are told apart")
  end,
  numbers_already_taken_are_skipped = function(t)
    t:eq(report.joinNames(instruments.unique({ "Handbells", "Handbells (2)", "Handbells" })),
      "Handbells, Handbells (2), Handbells (3)", "a number is never one another instrument already uses")
  end,
  records_for = function(t)
    local records = { r("Handbells I", 72), r("Handbells II", 74), r("Piano", 76) }
    local kept = instruments.recordsFor(records, { "Handbells II" })
    t:eq(#kept, 1, "only the second instrument is read")
    t:eq(kept[1].pitch, 74, "the record kept is the second instrument's")
    t:eq(#instruments.recordsFor(records, { "Handbells I", "Piano" }), 2, "two instruments keep both their records")
    t:eq(#instruments.recordsFor(records, {}), 0, "no instruments keeps nothing")
  end,
  named_keeps_score_order = function(t)
    local named = instruments.named({ "Handbells I", "Handbells II", "Piano" }, { "Piano", "Handbells I" })
    t:eq(#named, 2, "two instruments named")
    t:eq(named[1], "Handbells I", "score order is kept, not the order asked for")
  end,
}
