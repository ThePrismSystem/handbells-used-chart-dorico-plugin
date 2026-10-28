-- Parse Dorico's File.Export.Text CSV, which is the plug-in's window onto things Lua cannot read directly:
-- which instrument owns a voice stream (via marker texts), the project's file path, and whether flow
-- headings show (Text Frame rows). See docs/dorico-lua-guide.md, section 4.
local textexport = {}

-- Quote-aware: a quoted field may hold commas, doubled quotes and newlines.
function textexport.csvRows(csv)
  if csv:sub(1, 3) == string.char(239, 187, 191) then csv = csv:sub(4) end -- a UTF-8 byte-order mark, should one appear
  local rows, row, field = {}, {}, {}
  local i, n, quoted = 1, #csv, false
  local lineStart = 1
  while i <= n do
    local c = csv:sub(i, i)
    if not quoted and (c == "\n" or c == "\r") and i == lineStart then
      -- A blank line is no record: read as one, it would sit where a data row is looked for.
      if c == "\r" and csv:sub(i + 1, i + 1) == "\n" then i = i + 1 end
      lineStart = i + 1
    elseif quoted then
      if c == '"' then
        if csv:sub(i + 1, i + 1) == '"' then field[#field + 1] = '"'; i = i + 1 else quoted = false end
      else
        field[#field + 1] = c
      end
    elseif c == '"' then
      quoted = true
    elseif c == "," then
      row[#row + 1] = table.concat(field); field = {}
    elseif c == "\n" or c == "\r" then
      if c == "\r" and csv:sub(i + 1, i + 1) == "\n" then i = i + 1 end
      row[#row + 1] = table.concat(field); field = {}
      rows[#rows + 1] = row; row = {}
      lineStart = i + 1
    else
      field[#field + 1] = c
    end
    i = i + 1
  end
  if #field > 0 or #row > 0 then
    row[#row + 1] = table.concat(field)
    rows[#rows + 1] = row
  end
  return rows
end

-- The columns the plug-in reads. Each is "" when the export lacks it, so a column Dorico drops one day makes
-- the reads come back empty instead of taking the run down.
local COLUMNS = { "Path", "ID", "FlowNumber", "Instrument", "Page", "Type", "Text" }

-- Data rows as tables keyed by the header's column names.
function textexport.csvRecords(csv)
  local rows = textexport.csvRows(csv)
  local header = rows[1] or {}
  local records = {}
  for r = 2, #rows do
    local rec = {}
    for _, name in ipairs(COLUMNS) do rec[name] = "" end
    for idx, name in ipairs(header) do rec[name] = rows[r][idx] or "" end
    records[#records + 1] = rec
  end
  return records
end

-- {[streamId] = instrument} for marker texts starting with prefix; the ID column is flow-stream-event.
function textexport.streamOwners(csv, prefix)
  local owners = {}
  for _, rec in ipairs(textexport.csvRecords(csv)) do
    if rec.Text:sub(1, #prefix) == prefix then
      local streamId = tonumber(rec.ID:match("^%d+%-(%d+)%-%d+$"))
      if streamId then owners[streamId] = rec.Instrument end
    end
  end
  return owners
end

-- The project's file path from the first data row, or "" when the project has never been saved.
function textexport.projectPath(csv)
  local first = textexport.csvRecords(csv)[1]
  return first and first.Path or ""
end

-- {[flowNumber] = title} from the Flow Info (Title) rows, plus all = every title in the export. Flow numbers count
-- flows in score order from 1, and the rows are there whether or not flow headings show. Some projects (Steinberg's
-- Smith example) export them with no FlowNumber, in alphabetical order: then only all says anything.
function textexport.flowTitles(csv)
  local titles = { all = {} }
  for _, rec in ipairs(textexport.csvRecords(csv)) do
    if rec.Type == "Flow Info (Title)" then
      local n = tonumber(rec.FlowNumber)
      if n then titles[n] = rec.Text end
      titles.all[#titles.all + 1] = rec.Text
    end
  end
  return titles
end

-- Sorted "page|text" keys of the Text Frame rows.
function textexport.textFrameRows(csv)
  local rows = {}
  for _, rec in ipairs(textexport.csvRecords(csv)) do
    if rec.Type == "Text Frame" then rows[#rows + 1] = rec.Page .. "|" .. rec.Text end
  end
  table.sort(rows)
  return rows
end

local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

-- flowHeadingBehaviour as it was, from exports taken with it, with kNoFlowHeadings and with
-- kAddHeadingsAfterFirstFlow. Needs two or more flows (with one, the last two look the same).
function textexport.decideHeadings(originalCsv, noneCsv, afterFirstCsv)
  local original = textexport.textFrameRows(originalCsv)
  if same(original, textexport.textFrameRows(noneCsv)) then return "kNoFlowHeadings" end
  if same(original, textexport.textFrameRows(afterFirstCsv)) then return "kAddHeadingsAfterFirstFlow" end
  return "kAlwaysInsertHeadings"
end

-- Sorted "page|type|text|id" keys of every row that is on a page.
function textexport.pageRows(csv)
  local rows = {}
  for _, rec in ipairs(textexport.csvRecords(csv)) do
    if rec.Page ~= "" then rows[#rows + 1] = table.concat({ rec.Page, rec.Type, rec.Text, rec.ID }, "|") end
  end
  table.sort(rows)
  return rows
end

-- flowBreakBehaviour as it was, from exports taken with it, with kNoFlowBreaks and with kStartNewPageForFlows. Needs
-- the chart flow in place, so the music's pages move between the two. When nothing tells them apart, Dorico's
-- default.
function textexport.decideFlowBreaks(originalCsv, noBreaksCsv, newPageCsv)
  local original = textexport.pageRows(originalCsv)
  if same(original, textexport.pageRows(noBreaksCsv)) and not same(original, textexport.pageRows(newPageCsv)) then
    return "kNoFlowBreaks"
  end
  return "kStartNewPageForFlows"
end

return textexport
