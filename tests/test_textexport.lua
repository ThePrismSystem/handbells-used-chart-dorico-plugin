-- File.Export.Text CSV parsing: stream owners, project path, heading detection.
local textexport = require("hbuc.textexport")

local HEADER = '"Path","ID","FlowNumber","FlowName","Instrument","Page","Bar","Type","Text","Hidden"'

local function export(rows)
  local lines = { HEADER }
  for _, r in ipairs(rows) do lines[#lines + 1] = r end
  return table.concat(lines, "\r\n")
end

local function frames(list)
  local rows = {}
  for _, f in ipairs(list) do rows[#rows + 1] = '"","","","","","' .. f[1] .. '","","Text Frame","' .. f[2] .. '","N"' end
  rows[#rows + 1] = '"","","1","Chart","Global","","-1","Flow Info (Title)","Chart","N"'
  return export(rows)
end

return {
  stream_owners = function(t)
    local csv = export({
      '"","","","","","1","","Text Frame","Fixture","N"',
      '"","0-10-317","1","F","Handbells (A)","1","1","Staff-attached text (Default Text)","HBUCMAP10","N"',
      '"","0-13-319","1","F","Handbells, ""B""","1","1","Staff-attached text (Default Text)","HBUCMAP13","N"',
      '"","0-17-322","1","F","Organ","1","1","Staff-attached text (Default Text)","user text","N"',
    })
    local owners = textexport.streamOwners(csv, "HBUCMAP")
    t:eq(owners[10], "Handbells (A)")
    t:eq(owners[13], 'Handbells, "B"', "quoted owner")
    t:eq(owners[17], nil, "non-marker text ignored")
  end,
  quoted_newline = function(t)
    local csv = export({ '"","0-1-2","1","F","Organ","1","1","Staff-attached text","line one\nline two","N"',
      '"","0-1-3","1","F","Organ","1","1","Staff-attached text","after","N"' })
    local recs = textexport.csvRecords(csv)
    t:eq(#recs, 2, "a quoted field may hold a newline")
    t:eq(recs[1].Text, "line one\nline two")
    t:eq(recs[2].Text, "after")
  end,
  project_path = function(t)
    t:eq(textexport.projectPath(export({ '"C:/x/song.dorico","","","","","","","Project Info (Title)","Song","N"' })), "C:/x/song.dorico")
    t:eq(textexport.projectPath(export({ '"","","","","","","","Project Info (Title)","Song","N"' })), "", "never saved")
    t:eq(textexport.projectPath(HEADER), "", "no rows")
  end,
  bom_is_ignored = function(t)
    t:eq(textexport.projectPath("\239\187\191" .. export({ '"C:/x/song.dorico","","","","","","","Project Info (Title)","Song","N"' })),
      "C:/x/song.dorico", "a UTF-8 byte-order mark does not hide the Path column")
  end,
  text_frame_rows = function(t)
    t:eq(#textexport.textFrameRows(frames({ { 1, "Song" }, { 1, "1. Chart" }, { 2, "2. Song" } })), 3)
  end,
  decide_headings = function(t)
    local always = frames({ { 1, "Song" }, { 1, "1. Handbells Used Chart" }, { 2, "2. Song" } })
    local afterFirst = frames({ { 1, "Song" }, { 2, "2. Song" } })
    local none = frames({ { 1, "Song" } })
    t:eq(textexport.decideHeadings(always, none, afterFirst), "kAlwaysInsertHeadings")
    t:eq(textexport.decideHeadings(afterFirst, none, afterFirst), "kAddHeadingsAfterFirstFlow")
    t:eq(textexport.decideHeadings(none, none, afterFirst), "kNoFlowHeadings")
    t:eq(textexport.decideHeadings(frames({ { 2, "2. Song" }, { 1, "Song" } }), none, afterFirst),
      "kAddHeadingsAfterFirstFlow", "row order does not matter")
  end,
  flow_titles_by_number = function(t)
    local csv = export({
      '"C:/p.dorico","","1","Handbells Used Chart","Global","","-1","Flow Info (Title)","Handbells Used Chart","N"',
      '"C:/p.dorico","","2","Song","Global","","-1","Flow Info (Composer)","Someone","N"',
      '"C:/p.dorico","","2","Song","Global","","-1","Flow Info (Title)","Song","N"',
    })
    local titles = textexport.flowTitles(csv)
    t:eq(titles[1], "Handbells Used Chart")
    t:eq(titles[2], "Song")
    t:eq(titles[3], nil)
    t:eq(#titles.all, 2, "every title, numbered or not")
  end,
  unnumbered_flow_titles = function(t)
    -- Steinberg's Smith example exports its flows with no FlowNumber or FlowName, in alphabetical order
    local csv = export({
      '"C:/p.dorico","","","","Global","","-1","Flow Info (Title)","Handbells Used Chart","N"',
      '"C:/p.dorico","","","","Global","","-1","Flow Info (Title)","R. Amens","N"',
    })
    local titles = textexport.flowTitles(csv)
    t:eq(titles[1], nil, "no position can be read")
    t:eq(#titles.all, 2)
    t:eq(titles.all[1], "Handbells Used Chart")
  end,
  missing_columns_read_as_empty = function(t)
    -- An export without the Text, ID or Page columns names no owners rather than taking the run down.
    local csv = '"Path","Type"\r\n"","Text Frame"'
    t:eq(next(textexport.streamOwners(csv, "HBUCMAP")), nil, "no owners")
    t:eq(textexport.textFrameRows(csv)[1], "|", "a frame with no page or text")
  end,
  blank_lines_are_not_records = function(t)
    local csv = HEADER .. "\r\n\r\n" .. '"C:/x/song.dorico","","","","","","","Project Info (Title)","Song","N"' .. "\n\n"
    t:eq(#textexport.csvRecords(csv), 1, "blank lines are skipped")
    t:eq(textexport.projectPath(csv), "C:/x/song.dorico", "a blank line does not make a saved project look unsaved")
    t:eq(#textexport.csvRows('a\n""\nb'), 3, "a line holding an empty quoted field is still a row")
  end,
}
