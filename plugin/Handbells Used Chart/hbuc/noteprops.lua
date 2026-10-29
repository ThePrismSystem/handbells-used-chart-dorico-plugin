-- Each note's notehead set and colour, from a saved project's score (hbuc.dtn). Lua's propertyTable:get can't read
-- a value set by command or in Dorico's UI: such a value is stored with a context (a layout, and the note's block
-- instance), and Lua can only ask for the one without (docs/dorico-lua-guide.md, section 2). The saved score has
-- them all.
local dtn = require("hbuc.dtn")

local noteprops = {}

local DEFAULT_HEAD = "noteheadset.default"
local NOTES = { NoteEventDefinition = true, GraceNoteEventDefinition = true }
local KEPT = { kNoteheadSetOverride = true, kEventColour = true }

local function entryOf(tree, e)
  local typeNode, valueNode = dtn.child(tree, e, "propertyType"), dtn.child(tree, e, "value")
  local property = typeNode and dtn.value(tree, typeNode)
  if not KEPT[property] or not valueNode then return nil end
  local raw = dtn.value(tree, valueNode)
  local layout, instance = -1, -1
  local context = dtn.child(tree, e, "context")
  if context then
    -- Read as -1, a context in a form not seen before could put a part's value on the full score, so it stops the
    -- read instead.
    local l, b = dtn.child(tree, context, "layoutIDWithFrameChainID"), dtn.child(tree, context, "blockInstanceID")
    if l then
      -- "steamVariantList:list: {int: 0}, {int: -1}, {bool: false}": the first int is the layout
      local text = dtn.value(tree, l)
      layout = tonumber(text:match("^steamVariantList:list: {int: (%-?%d+)}"))
      if not layout then error("noteprops: a layout the plug-in can't read: " .. text, 0) end
    end
    if b then
      local text = dtn.value(tree, b)
      instance = tonumber(text)
      if not instance then error("noteprops: a block instance the plug-in can't read: " .. text, 0) end
    end
  end
  return { property = property, value = raw:match('^string: "(.*)"$') or raw, layout = layout, instance = instance }
end

-- {[eventId] = {{property, value, layout, instance}}} for every note and grace note, holding only its notehead set
-- and colour entries (none for most notes). layout and instance are -1 for "every" and "any".
function noteprops.fromTree(tree)
  local out = {}
  for id = 0, tree.count - 1 do
    if NOTES[dtn.name(tree, id)] then
      local idNode = dtn.child(tree, id, "eventID")
      local eventId = idNode and tonumber(dtn.value(tree, idNode))
      if not eventId then error("noteprops: node " .. id .. " is a note with no event id", 0) end
      local list = {}
      local table_ = dtn.child(tree, id, "propertyTable")
      local entries = table_ and dtn.child(tree, table_, "entries")
      for _, e in ipairs(entries and dtn.children(tree, entries) or {}) do
        list[#list + 1] = entryOf(tree, e)
      end
      out[eventId] = list
    end
  end
  return out
end

-- The value that applies to a note in layoutId and block instance: only entries for that layout or every layout,
-- and that instance or any, count, and the more specific wins (the layout first).
local function pick(entries, property, layoutId, instance)
  local best, bestRank
  for _, e in ipairs(entries) do
    if e.property == property and (e.layout == layoutId or e.layout == -1)
      and (e.instance == instance or e.instance == -1) then
      local rank = (e.layout == layoutId and 2 or 0) + (e.instance == instance and 1 or 0)
      if not bestRank or rank > bestRank then best, bestRank = e.value, rank end
    end
  end
  return best
end

-- The notehead set id that applies, the default set when none does.
function noteprops.head(entries, layoutId, instance)
  local value = pick(entries, "kNoteheadSetOverride", layoutId, instance)
  if value == nil or value == "" then return DEFAULT_HEAD end
  return value
end

-- The colour that applies as "#rrggbb", or "". Lua writes "#rrggbb"; a command, "#aarrggbb".
function noteprops.colour(entries, layoutId, instance)
  local hex = tostring(pick(entries, "kEventColour", layoutId, instance) or ""):match("^#(%x+)$")
  if hex and (#hex == 6 or #hex == 8) then return "#" .. hex:sub(-6):lower() end
  return ""
end

return noteprops
