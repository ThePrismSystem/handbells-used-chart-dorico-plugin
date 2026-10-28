-- Where a chart goes in Dorico: which chart players it needs (slots), which existing ones an update reuses, and
-- what each section writes, at which positions and with which spellings, notehead set and colour.
local bellname = require("hbuc.bellname")
local constants = require("hbuc.constants")
local options = require("hbuc.options")
local shapes = require("hbuc.shapes")

local chartlayout = {}

-- SMBs are charted on one treble staff; every other kind on a grand staff.
function chartlayout.roleOf(kind)
  if kind == "smbs" then return "treble" end
  return "grand"
end

-- One slot per (owners, role) in order of first use; sets section.slot. Combined sections all share one owner
-- string, so a combined chart needs at most a grand and a treble slot.
function chartlayout.slots(sections)
  local slots, index = {}, {}
  for _, section in ipairs(sections) do
    local owner = table.concat(section.owners or {}, "|")
    local role = chartlayout.roleOf(section.kind)
    local key = owner .. "\0" .. role
    if not index[key] then
      slots[#slots + 1] = { role = role, owner = owner }
      index[key] = #slots
    end
    section.slot = index[key]
  end
  return slots
end

-- existing: {{key, role}} in marker order. keys[i] is the reused key for slot i, or false for a player to add.
function chartlayout.assign(slots, existing)
  local used, keys, surplus = {}, {}, {}
  for i, slot in ipairs(slots) do
    keys[i] = false
    for j, e in ipairs(existing or {}) do
      if not used[j] and e.role == slot.role then
        keys[i] = e.key
        used[j] = true
        break
      end
    end
  end
  for j, e in ipairs(existing or {}) do
    if not used[j] then surplus[#surplus + 1] = e.key end
  end
  return { keys = keys, surplus = surplus }
end

-- A grand-staff chart player sounds an octave up, so the bell's own (sounding) spelling is written; the
-- Glockenspiel sounds two octaves up, so it is given the spelling an octave above the bell.
-- MIDI's top note: Dorico's MIDIPitchWithSpelling is never given anything above it, since a constructor given a bad
-- argument can crash Dorico. Only the highest SMBs (G#8 and up) reach it; they are left out and named.
local TOP = 127

local function spellColumns(columns, role, unwritable)
  local out = {}
  for c, entries in ipairs(columns or {}) do
    local spellings = {}
    for _, e in ipairs(entries) do
      local pitch, diatonic = e.pitch, e.diatonic
      if role == "treble" then pitch, diatonic = pitch + 12, diatonic + 7 end
      local s = pitch <= TOP and bellname.toSpelling(pitch, diatonic) or nil
      if s then
        spellings[#spellings + 1] = s
      elseif pitch > TOP then
        unwritable[#unwritable + 1] = bellname.nameOf(e.pitch, e.diatonic).name
      end
    end
    out[c] = spellings
  end
  return out
end

-- sections: plan sections with .slot set. choices: {shapes, colours, heads, headNames} keyed by kind (headNames by
-- notehead set id).
function chartlayout.build(sections, choices)
  local built, warnings, warned, unwritable = {}, {}, {}, {}
  local start = 0
  for _, section in ipairs(sections) do
    local kind = section.kind
    local head = (choices.heads or {})[kind]
    local shape = shapes.chartShape((choices.shapes or {})[kind], head, (choices.headNames or {})[head or ""], kind)
    local set = shapes.noteheadSetFor(shape)
    if not set and not warned[kind] then
      warned[kind] = true
      warnings[#warnings + 1] = { type = "missing-notehead", instrument = constants.KIND_NAME[kind], names = { shape } }
    end
    local role = chartlayout.roleOf(kind)
    built[#built + 1] = {
      kind = kind,
      slot = section.slot,
      label = section.label,
      start = start,
      columns = section.columns,
      noteheadSet = set,
      colour = options.canonicalColour(options.sectionColour(kind, choices.colours or {})),
      treble = spellColumns(section.treble, role, unwritable),
      bass = spellColumns(section.bass, role, unwritable),
    }
    start = start + section.columns
  end
  if #unwritable > 0 then warnings[#warnings + 1] = { type = "unwritable", names = unwritable } end
  return { sections = built, warnings = warnings }
end

-- The marker's per-section entries: kind, the chart player's key and the column count.
function chartlayout.markerSections(built, slotKeys)
  local out = {}
  for i, s in ipairs(built.sections) do
    out[i] = { kind = s.kind, player = slotKeys[s.slot], columns = s.columns }
  end
  return out
end

local function has(list, key)
  for _, k in ipairs(list) do
    if k == key then return true end
  end
  return false
end

-- The full score: the lowest-numbered layout holding every music player. layouts: {{id, keys}}.
function chartlayout.fullScoreLayout(layouts, musicKeys)
  local best
  for _, l in ipairs(layouts) do
    local all = true
    for _, k in ipairs(musicKeys) do
      if not has(l.keys, k) then all = false end
    end
    if all and (best == nil or l.id < best) then best = l.id end
  end
  return best
end

-- Layouts other than the full score whose players are all chart players: the parts Dorico made for them.
function chartlayout.partLayouts(layouts, chartKeys, fullId)
  local ids = {}
  for _, l in ipairs(layouts) do
    if l.id ~= fullId and #l.keys > 0 then
      local only = true
      for _, k in ipairs(l.keys) do
        if not has(chartKeys, k) then only = false end
      end
      if only then ids[#ids + 1] = l.id end
    end
  end
  table.sort(ids)
  return ids
end

-- The full score's flowHeadingBehaviour while the chart is its first flow, from the one it had before. With one
-- music flow, none: the title now heads page 1, above the chart, and the flow's heading would print it twice. With
-- several, hiding every heading would lose each later flow's, so only the chart's goes, and the first music flow
-- gains one if it had none.
function chartlayout.chartHeadings(original, musicFlows)
  if original == "kNoFlowHeadings" or musicFlows <= 1 then return "kNoFlowHeadings" end
  return "kAddHeadingsAfterFirstFlow"
end

-- The full score's flowBreakBehaviour while the chart is there: a new page for each flow (Dorico's default), or
-- none, so the music follows the chart on the same page. It's one setting for the whole layout, so without breaks
-- every later music flow runs on from the one before as well.
function chartlayout.flowBreaks(newPage)
  return newPage and "kStartNewPageForFlows" or "kNoFlowBreaks"
end

return chartlayout
