-- The chart plan, ported from the Sibelius plugin's Plan.mss: which sections to draw, their labels and
-- columns, for the instruments the dialog selected, charted together or one set per instrument.
local collect = require("hbuc.collect")
local columns = require("hbuc.columns")
local constants = require("hbuc.constants")
local instruments = require("hbuc.instruments")

local plan = {}

function plan.kindName(kind)
  return constants.KIND_NAME[kind] or constants.KIND_NAME.bells
end

-- The label counts physical bells, so two spellings of one pitch count once.
local function distinctPitches(entries)
  local seen, total = {}, 0
  for _, e in ipairs(entries) do
    if not seen[e.pitch] then
      seen[e.pitch] = true
      total = total + 1
    end
  end
  return total
end

local function makeSection(kind, entries)
  local built = columns.build(entries, columns.usesOneStaff(kind))
  return {
    kind = kind,
    label = plan.kindName(kind) .. " Used: " .. distinctPitches(entries),
    columns = built.length,
    treble = built.treble,
    bass = built.bass,
  }
end

-- Sections and warnings for one set of records (BuildPlan).
function plan.buildOne(records, heads)
  local collected = collect.bells(records, heads)
  local sections = {}
  for _, kind in ipairs(constants.KINDS) do
    if #collected[kind] > 0 then sections[#sections + 1] = makeSection(kind, collected[kind]) end
  end
  local warnings = {}
  if collected.unknown > 0 then
    warnings[#warnings + 1] = { type = "unknown-notehead", count = collected.unknown, names = collected.unknownNames }
  end
  if collected.unreadable > 0 then
    warnings[#warnings + 1] = { type = "unreadable-pitch", count = collected.unreadable, names = {} }
  end
  if #collected.outOfRange > 0 then
    warnings[#warnings + 1] = { type = "out-of-range", count = #collected.outOfRange, names = collected.outOfRange }
  end
  return { sections = sections, warnings = warnings }
end

local function copy(list)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  return out
end

-- The plan for the selected instruments (BuildChartPlan). options: {heads, instruments = {name...}, mode}.
-- Charting apart needs two instruments to mean anything, so one instrument is always charted combined.
function plan.build(records, options)
  local names = options.instruments or {}
  -- Warnings are about notes, not instruments: read once over everything selected.
  local combined = plan.buildOne(instruments.recordsFor(records, names), options.heads)
  local emptyNames = {}

  if options.mode ~= "separate" or #names < 2 then
    for _, section in ipairs(combined.sections) do
      section.plainLabel = section.label
      section.owners = copy(names)
    end
    return { sections = combined.sections, warnings = combined.warnings, emptyNames = emptyNames }
  end

  local sections = {}
  for _, name in ipairs(names) do
    local own = plan.buildOne(instruments.recordsFor(records, { name }), options.heads)
    -- Named rather than silently dropped: a choir the user asked for that charts nothing.
    if #own.sections == 0 then emptyNames[#emptyNames + 1] = name end
    for _, section in ipairs(own.sections) do
      section.plainLabel = section.label
      section.label = name .. constants.LABEL_DASH .. section.label
      section.owners = { name }
      sections[#sections + 1] = section
    end
  end
  return { sections = sections, warnings = combined.warnings, emptyNames = emptyNames }
end

return plan
