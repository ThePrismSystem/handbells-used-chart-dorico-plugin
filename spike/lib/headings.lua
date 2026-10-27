-- Recover the full score's flowHeadingBehaviour, which Lua cannot read, from text exports: flow headings
-- appear in the export as Text Frame rows, so the export under each candidate setting is compared with
-- the export as it stands. Run it once the chart flow exists (two or more flows): with a single flow,
-- kNoFlowHeadings and kAddHeadingsAfterFirstFlow look the same.
local streammap = require("streammap")
local layoutopts = require("layoutopts")

local headings = {}

-- Sorted "page|text" keys of the export's Text Frame rows.
function headings.textFrameRows(csv)
  local rows = {}
  for _, rec in ipairs(streammap.csvRecords(csv)) do
    if rec.Type == "Text Frame" then rows[#rows + 1] = rec.Page .. "|" .. rec.Text end
  end
  table.sort(rows)
  return rows
end

local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

-- Exports taken with the original setting, with kNoFlowHeadings and with kAddHeadingsAfterFirstFlow.
function headings.decide(originalCsv, noneCsv, afterFirstCsv)
  local original = headings.textFrameRows(originalCsv)
  if same(original, headings.textFrameRows(noneCsv)) then return "kNoFlowHeadings" end
  if same(original, headings.textFrameRows(afterFirstCsv)) then return "kAddHeadingsAfterFirstFlow" end
  return "kAlwaysInsertHeadings"
end

local function exportCsv(app, name)
  local base = require("rundir")() .. name
  os.remove(base .. ".csv")
  app:doCommand("File.Export.Text?File=" .. base .. ".txt&Show=false")
  local f = assert(io.open(base .. ".csv", "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

-- Returns the layout's current flowHeadingBehaviour and leaves it set to that value.
function headings.detect(app, score, layoutId)
  local function set(value)
    app:doCommand(layoutopts.setCommand(score.openScoreID, layoutId, { flowHeadingBehaviour = value }))
  end
  local original = exportCsv(app, "headings-original")
  set("kNoFlowHeadings")
  local none = exportCsv(app, "headings-none")
  set("kAddHeadingsAfterFirstFlow")
  local afterFirst = exportCsv(app, "headings-afterfirst")
  local value = headings.decide(original, none, afterFirst)
  set(value)
  return value
end

return headings
