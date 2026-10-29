-- The end-of-run report, ported from the Sibelius plugin's Report.mss and the summary Chart.mss composes.
local constants = require("hbuc.constants")

local report = {}

function report.joinNames(names)
  return table.concat(names or {}, ", ")
end

-- One branch per warning type; a type this code does not know is dropped rather than taking the run down
-- inside the code meant to explain a problem.
function report.warningLines(warnings)
  local lines = {}
  for _, w in ipairs(warnings) do
    local line = ""
    if w.type == "unknown-notehead" then
      line = w.count .. " note(s) with an unrecognised notehead were skipped"
      if w.names and #w.names > 0 then line = line .. ": " .. report.joinNames(w.names) end
    elseif w.type == "unreadable-pitch" then
      -- Notes the dumps list but no read copy carried a notehead for (docs/dorico-lua-guide.md, section 3).
      line = string.format("%d note(s) could not be read and were skipped", w.count)
    elseif w.type == "out-of-range" then
      line = "Bells outside C2-C9 were skipped: " .. report.joinNames(w.names)
    elseif w.type == "missing-notehead" then
      -- Raised while drawing: a chart shape Dorico has no notehead set for is drawn round instead.
      line = (w.instrument or "Some bells") .. " were drawn as round notes: Dorico has no " .. report.joinNames(w.names)
        .. " notehead set"
    elseif w.type == "merged-notes" then
      line = string.format("%d note(s) sounded in unison with another voice and were read as one: if those voices"
        .. " use different noteheads, check the chart", w.count)
    elseif w.type == "musicxml-missing" then
      local flows = {}
      for i, n in ipairs(w.flows or {}) do flows[i] = tostring(n) end
      local several = #flows > 1
      -- left out of the export, or its file no longer matches: either way it has no file of its own
      line = (several and "Flows " or "Flow ") .. table.concat(flows, ", ") .. (several and " have" or " has")
        .. " noteheads changed in Dorico but no matching MusicXML file, so those noteheads are listed as "
        .. constants.NOT_IN_MUSICXML_NAME
    elseif w.type == "unwritable" then
      -- The SMB staff (a Glockenspiel) sounds two octaves up, past MIDI's top note for the highest bells.
      line = "Bells too high to draw on the SMB staff were skipped: " .. report.joinNames(w.names)
    end
    if line ~= "" then lines[#lines + 1] = line end
  end
  return table.concat(lines, "\n")
end

local function withWarnings(warnings, text)
  local lines = report.warningLines(warnings)
  if lines == "" then return text end
  return lines .. "\n\n" .. text
end

-- The message at the end of a charting run. removedExisting: the run replaced a chart that was there.
-- keptExisting: a chart was already there, and a run that charts nothing leaves it as it was.
function report.summary(plan, removedExisting, extra, keptExisting)
  local M = constants.MESSAGES
  -- Warnings found while drawing or reading join the plan's own, after them.
  local warnings = {}
  for _, w in ipairs(plan.warnings or {}) do warnings[#warnings + 1] = w end
  for _, w in ipairs(extra or {}) do warnings[#warnings + 1] = w end
  plan = { sections = plan.sections, warnings = warnings, emptyNames = plan.emptyNames }
  if #plan.sections == 0 then
    local text = M.noBellsFound
    if removedExisting then text = text .. "\n\n" .. M.chartWasRemoved end
    if keptExisting then text = text .. "\n\n" .. M.chartLeftAsItWas end
    return withWarnings(plan.warnings, text)
  end
  local labels = {}
  for i, section in ipairs(plan.sections) do labels[i] = section.label end
  local text = table.concat(labels, "\n")
  if plan.emptyNames and #plan.emptyNames > 0 then
    text = text .. "\n" .. M.nothingToChartFor .. " " .. report.joinNames(plan.emptyNames)
  end
  if removedExisting then text = text .. "\n\n" .. M.chartWasReplaced end
  return withWarnings(plan.warnings, text)
end

return report
