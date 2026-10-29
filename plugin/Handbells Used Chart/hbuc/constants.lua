-- Score-facing text and fixed values, copied from the Sibelius plugin's tools/plugins.json so both plugins
-- label and report charts the same way.
local constants = {}

-- The instruments a chart can hold, in the order sections are drawn.
constants.KINDS = { "bells", "chimes", "smbs", "pf", "whitechapel" }

-- The plural name each kind is labelled with: "<name> Used: n".
constants.KIND_NAME = {
  bells = "Handbells",
  chimes = "Handchimes",
  smbs = "SMBs",
  pf = "P&F Handbells",
  whitechapel = "Whitechapel Handbells",
}

-- Separates an instrument's name from its chart's label: "Handbells I - Handbells Used: 25".
constants.LABEL_DASH = " - "

constants.NO_NOTEHEAD = "(no notehead)"
-- Noteheads read from a MusicXML export (shapes.fromMusicXML): one changed in Dorico to a set the export can't
-- express, and a value no built-in set writes.
constants.NOT_IN_MUSICXML_NAME = "Changed in Dorico (not in MusicXML)"
constants.MUSICXML_HEAD_NAME = "%s (MusicXML)"
constants.SHAPE_MATCH = "(match notehead)"
constants.SHAPES = { "Round", "Diamond", "Square", "Triangle", "Inverted triangle", "Half circle", "Cone" }

constants.CHART_MODE_COMBINED = "One combined chart"
constants.CHART_MODE_SEPARATE = "A separate chart for each instrument"

constants.MARKER_PREFIX = "HBUC"
-- A text the run puts at the start of the music for a moment, to see where the music starts (writechart).
constants.PAGE_PROBE = "HBUC page probe"
constants.MARKER_VERSION = "2"

-- The chart's own flow, which also carries page 1's title block.
constants.CHART_FLOW_NAME = "Handbells Used Chart"

-- What a chart player is called while Dorico's Delete Empty Players lists it (its name is a space otherwise).
constants.CHART_PLAYER_LEFT = "Handbells Used Chart %d"

-- Chart players: a grand staff that sounds an octave up (bell = sounding), and a single treble staff for SMBs
-- that sounds two octaves up.
constants.GRAND_INSTRUMENT = "instrument.pitchedpercussion.handbells"
constants.TREBLE_INSTRUMENT = "instrument.pitchedpercussion.glockenspiel"

constants.MESSAGES = {
  noBellsFound = "No handbells or handchimes were found in this score.",
  chartWasRemoved = "The existing chart was removed.",
  chartWasReplaced = "An existing chart was replaced.",
  noChartToRemove = "This score carries no chart that this plug-in made.",
  sameNoteheadChosen = "Choose a different notehead for one of them and run the plug-in again.",
  noInstrumentSelected = "Select at least one instrument to chart, then run the plug-in again.",
  nothingToChartFor = "Nothing to chart for:",
  -- Dorico's own, filled with string.format where they hold a %s or %d
  noProject = "Open a project with one or more players and run the plug-in again.",
  untestedDorico = "Handbells Used Chart needs Dorico 6. This is Dorico %s, so nothing was changed.",
  chartLeftAsItWas = "The existing chart was left as it was.",
  notSaved = "Save this project first, then run the plug-in again. The plug-in saves the project before it draws a"
    .. " chart, so File > Revert can take the whole run back.",
  chartUnidentified = "This project has a chart that this plug-in cannot positively identify, so nothing was changed: %s",
  chartKept = "The chart was kept, because its flow was not deleted.",
  notFullScore = "Show the full score (not a part) in the project window, then run the plug-in again.",
  saveFailed = "The project could not be saved, so nothing was drawn or removed. Save it with File > Save, then run"
    .. " the plug-in again.",
  readFailed = "The plug-in could not read this project's music, so nothing was changed: %s\n\nThe run log is at %s.",
  scratchLeft = "The plug-in could not take away the temporary flow it used to read the music. Delete flow %d in"
    .. " Setup mode. Nothing else was changed.",
  writeFailed = "The chart could not be finished: %s\n\nUse File > Revert to return to the project as it was before"
    .. " the run. The run log is at %s.",
  -- an error the run's own steps did not catch, before the project was saved (after it, writeFailed)
  runFailed = "The plug-in stopped with an error, so nothing was changed: %s\n\nThe run log is at %s.",
  -- the run could not even begin: no folder for its files, or a module that would not load
  startFailed = "The plug-in could not start, so nothing was changed: %s",
  chartRemovedOptionsLeft = "The existing chart was removed, but the full score's layout options could not be put"
    .. " back as they were: check its flow headings, whether flows start on a new page, hidden staves and staff labels"
    .. " in Layout Options.",
  -- the MusicXML step, for scores whose noteheads were changed in Dorico
  musicxmlNeeded = "Some noteheads in this score were changed in Dorico, and a plug-in can't read which notehead each"
    .. " one is. To tell handbells, handchimes and the other kinds apart, the plug-in reads them from a MusicXML export"
    .. " of the score instead.\n\nExport MusicXML opens Dorico's export dialog. Its starting settings are fine, so"
    .. " click OK there. Choose file is for an export you've already made.",
  musicxmlCompressed = "That file is compressed MusicXML (.mxl), which the plug-in can't read. Export again with"
    .. " \"Export uncompressed XML (.musicxml)\" selected.",
  musicxmlUnreadable = "%s isn't a MusicXML file the plug-in can read, so nothing was changed.",
  musicxmlOlder = "This export is older than the project's last save, so it may not show noteheads changed since."
    .. " Use it anyway?",
  musicxmlMismatch = "The MusicXML export doesn't match the music in flow %d, so nothing was changed. Run the plug-in"
    .. " again, click Export MusicXML, and choose the new export's full-score file.",
}

-- The plug-in's own version; the dialog's response must carry the same one.
constants.VERSION = "0.1.0"

-- The Dorico major version the plug-in runs on (any build of it).
constants.DORICO_MAJOR = "6"

-- The dialog's fixed text, as the Sibelius dialog has it (minus the parts options).
constants.DIALOG = {
  title = "Create a Handbells/Handchimes/SMBs Used Chart",
  resultsTitle = "Handbells Used Chart",
  instruments = "Instruments to Chart",
  charts = "Charts",
  noteheadHeader = "Notehead in Music",
  shapeHeader = "Chart Shape",
  remove = "Remove Existing Chart",
  newPage = "Start the music on a new page",
  saveNote = "The project is saved before the chart is drawn.",
  chartColumn = "Chart",
  instrumentColumn = "Instrument",
  writtenHeader = "Written as",
  writtenHandbells = "Handbells instrument (sounds an octave higher)",
  writtenAtPitch = "At pitch (e.g. Piano or Organ)",
  -- the Mac dialog's alert when it cannot show itself; nothing is changed
  dialogFailed = "The dialog could not be shown, so nothing was changed.",
  cancel = "Cancel",
  ok = "OK",
  -- the MusicXML step's buttons and picker
  exportMusicXML = "Export MusicXML",
  chooseFile = "Choose file",
  removeChart = "Remove chart",
  useAnyway = "Use it anyway",
  back = "Back",
  pickTitle = "Choose the MusicXML export",
  pickFilter = "MusicXML",
}

-- Handbells are always black, so they have no colour field.
constants.KIND_COLOUR_LABEL = {
  chimes = "Handchime Color",
  smbs = "SMBs Color",
  pf = "P&F Color",
  whitechapel = "Whitechapel Color",
}

return constants
