-- Ported from the Sibelius plugin's test/TestReport.mss, with the missing-notehead line rewritten for Dorico
-- (a shape with no notehead set is drawn round), plus the end-of-run summary Chart.mss composes.
local report = require("hbuc.report")
local constants = require("hbuc.constants")

local M = constants.MESSAGES

return {
  join_names = function(t)
    t:eq(report.joinNames({}), "", "no names joins to nothing")
    t:eq(report.joinNames({ "C2" }), "C2", "one name needs no separator")
    t:eq(report.joinNames({ "C2", "B9" }), "C2, B9", "two names are comma separated")
  end,
  warning_lines = function(t)
    t:eq(report.warningLines({}), "", "no warnings makes no lines")
    t:eq(report.warningLines({ { type = "unknown-notehead", count = 3, names = {} } }),
      "3 note(s) with an unrecognised notehead were skipped")
    t:eq(report.warningLines({ { type = "unknown-notehead", count = 64, names = { "Diamond Noteheads", "X Noteheads" } } }),
      "64 note(s) with an unrecognised notehead were skipped: Diamond Noteheads, X Noteheads")
    t:eq(report.warningLines({ { type = "unreadable-pitch", count = 1, names = {} } }),
      "1 note(s) could not be read and were skipped")
    t:eq(report.warningLines({ { type = "out-of-range", count = 2, names = { "C0", "B9" } } }),
      "Bells outside C2-C9 were skipped: C0, B9")
  end,
  unknown_types_are_dropped = function(t)
    t:eq(report.warningLines({
      { type = "unknown-notehead", count = 3, names = {} },
      { type = "something-else", count = 9, names = {} },
      { type = "out-of-range", count = 1, names = { "C0" } },
    }), "3 note(s) with an unrecognised notehead were skipped\nBells outside C2-C9 were skipped: C0")
  end,
  missing_notehead = function(t)
    t:eq(report.warningLines({ { type = "missing-notehead", count = 0, names = { "Half circle" }, instrument = "SMBs" } }),
      "SMBs were drawn as round notes: Dorico has no Half circle notehead set")
  end,
  summary_with_sections = function(t)
    local plan = { sections = { { label = "Handbells Used: 20" }, { label = "SMBs Used: 14" } }, warnings = {}, emptyNames = {} }
    t:eq(report.summary(plan, false), "Handbells Used: 20\nSMBs Used: 14")
  end,
  summary_with_warnings = function(t)
    local plan = {
      sections = { { label = "Handbells (A) - Handbells Used: 20" } },
      warnings = { { type = "out-of-range", count = 1, names = { "B1" } } },
      emptyNames = { "Organ" },
    }
    t:eq(report.summary(plan, true),
      "Bells outside C2-C9 were skipped: B1\n\nHandbells (A) - Handbells Used: 20\n" .. M.nothingToChartFor
        .. " Organ\n\n" .. M.chartWasReplaced)
  end,
  no_bells_found_text = function(t)
    local plan = { sections = {}, warnings = { { type = "out-of-range", count = 1, names = { "B1" } } }, emptyNames = {} }
    t:eq(report.summary(plan, false), "Bells outside C2-C9 were skipped: B1\n\n" .. M.noBellsFound)
    t:eq(report.summary({ sections = {}, warnings = {}, emptyNames = {} }, true), M.noBellsFound .. "\n\n" .. M.chartWasRemoved)
  end,
  the_unread_notes_line_is_gone = function(t)
    t:eq(report.warningLines({ { type = "unread-notes", count = 3 } }), "", "collect's unreadable count says it once")
  end,
  merged_and_unwritable_lines = function(t)
    t:eq(report.warningLines({ { type = "merged-notes", count = 2 } }),
      "2 note(s) sounded in unison with another voice and were read as one: if those voices use different"
        .. " noteheads, check the chart")
    t:eq(report.warningLines({ { type = "unwritable", names = { "G#8", "C9" } } }),
      "Bells too high to draw on the SMB staff were skipped: G#8, C9")
  end,
  flows_missing_from_the_musicxml_export_are_named = function(t)
    -- a flow Dorico's export left out, or one whose file no longer matches it: either way, no file of its own
    t:eq(report.warningLines({ { type = "musicxml-missing", flows = { 1, 3 } } }),
      "Flows 1, 3 have noteheads changed in Dorico but no matching MusicXML file, so those noteheads are listed as"
        .. " Changed in Dorico (not in MusicXML)")
    t:eq(report.warningLines({ { type = "musicxml-missing", flows = { 1 } } }),
      "Flow 1 has noteheads changed in Dorico but no matching MusicXML file, so those noteheads are listed as"
        .. " Changed in Dorico (not in MusicXML)")
  end,
  musicxml_lines_name_the_notehead_such_notes_were_grouped_with = function(t)
    t:eq(report.warningLines({ { type = "musicxml-missing", flows = { 2 }, as = "Diamond Noteheads" } }),
      "Flow 2 has noteheads changed in Dorico but no matching MusicXML file, so those noteheads are listed as"
        .. " Diamond Noteheads")
    t:eq(report.warningLines({ { type = "musicxml-unmatched", count = 1, as = "Diamond Noteheads" } }),
      "1 note(s) with noteheads changed in Dorico couldn't be found in the MusicXML export, so they are listed as"
        .. " Diamond Noteheads")
  end,
  changed_notes_the_musicxml_file_lacks_are_counted = function(t)
    t:eq(report.warningLines({ { type = "musicxml-unmatched", count = 2 } }),
      "2 note(s) with noteheads changed in Dorico couldn't be found in the MusicXML export, so they are listed as"
        .. " Changed in Dorico (not in MusicXML)")
  end,
  nothing_charted_says_the_chart_was_left = function(t)
    local plan = { sections = {}, warnings = {}, emptyNames = {} }
    t:eq(report.summary(plan, false, {}, true), M.noBellsFound .. string.rep(string.char(10), 2) .. M.chartLeftAsItWas)
    t:eq(M.chartLeftAsItWas, "The existing chart was left as it was.")
    t:eq(report.summary(plan, false, {}, false), M.noBellsFound, "no chart, nothing to say about one")
  end,
  extra_warnings_join_plan_warnings = function(t)
    local plan = {
      sections = { { label = "Handbells Used: 2" } },
      warnings = { { type = "out-of-range", count = 1, names = { "B1" } } },
      emptyNames = {},
    }
    local extra = { { type = "missing-notehead", instrument = "Handchimes", names = { "Cone" } } }
    t:eq(report.summary(plan, false, extra),
      "Bells outside C2-C9 were skipped: B1\nHandchimes were drawn as round notes: Dorico has no Cone notehead set"
        .. "\n\nHandbells Used: 2")
    t:eq(#plan.warnings, 1, "the plan's own list is left alone")
  end,
  run_messages = function(t)
    t:eq(M.noProject, "Open a project with one or more players and run the plug-in again.")
    t:eq(string.format(M.untestedDorico, "5.1.81"),
      "Handbells Used Chart needs Dorico 6. This is Dorico 5.1.81, so nothing was changed.")
    t:eq(M.chartKept, "The chart was kept, because its flow was not deleted.")
    t:eq(string.format(M.scratchLeft, 3),
      "The plug-in could not take away the temporary flow it used to read the music. Delete flow 3 in Setup mode."
        .. " Nothing else was changed.")
  end,
  warnings_missing_fields_still_make_lines = function(t)
    t:eq(report.warningLines({ { type = "missing-notehead", names = { "Half circle" } } }),
      "Some bells were drawn as round notes: Dorico has no Half circle notehead set")
    t:eq(report.joinNames(nil), "", "no names at all")
  end,
}
