-- Each note's notehead set and colour, from a saved project's score (hbuc.dtn). Lua's propertyTable:get can't read
-- a value set by command or in Dorico's UI: such a value is stored with a context (a layout, and the note's block
-- instance), and Lua can only ask for the one without (docs/dorico-lua-guide.md, section 2). The saved score has
-- them all.
local constants = require("hbuc.constants")
local dtn = require("hbuc.dtn")

local noteprops = {}

local NOTES = { NoteEventDefinition = true, GraceNoteEventDefinition = true }
local KEPT = { kNoteheadSetOverride = true, kEventColour = true }
-- The other children a context may have, and their values: a notehead's has the empty offset, a colour's this one.
local OTHER = {
  propertyOffset = { [""] = true, ['string: "0:0:1:0"'] = true },
  assignedStaveType = { kNormal = true },
}

local function unreadable(name, text)
  error("noteprops: a context the plug-in can't read: " .. name .. " = " .. text, 0)
end

-- A notehead or colour entry's layout and block instance. In the projects Dorico 6.2 saved, a context has both of
-- these, sometimes an offset and a stave type, and only the values allowed here. Read as -1, a context in a form not
-- seen before could put a part's value on the full score, so it stops the read instead.
local function contextOf(tree, context)
  local layout, instance
  for _, c in ipairs(dtn.children(tree, context)) do
    local name, text = dtn.name(tree, c), dtn.value(tree, c)
    if name == "layoutIDWithFrameChainID" then
      -- the layout, then the frame chain, which was -1 for every note seen
      layout = tonumber(text:match("^steamVariantList:list: {int: (%-?%d+)}, {int: %-1}, {bool: false}$"))
      if not layout then unreadable(name, text) end
    elseif name == "blockInstanceID" then
      instance = tonumber(text:match("^%-?%d+$"))
      if not instance then unreadable(name, text) end
    elseif not (OTHER[name] and OTHER[name][text]) then
      unreadable(name, text)
    end
  end
  if not layout then error("noteprops: a context with no layout", 0) end
  if not instance then error("noteprops: a context with no block instance", 0) end
  return layout, instance
end

local function entryOf(tree, e)
  local typeNode, valueNode = dtn.child(tree, e, "propertyType"), dtn.child(tree, e, "value")
  local property = typeNode and dtn.value(tree, typeNode)
  if not KEPT[property] or not valueNode then return nil end
  local raw = dtn.value(tree, valueNode)
  local layout, instance = -1, -1
  local context = dtn.child(tree, e, "context")
  if context then layout, instance = contextOf(tree, context) end
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
      local propertyTable = dtn.child(tree, id, "propertyTable")
      local entries = propertyTable and dtn.child(tree, propertyTable, "entries")
      for _, e in ipairs(entries and dtn.children(tree, entries) or {}) do
        list[#list + 1] = entryOf(tree, e)
      end
      out[eventId] = list
    end
  end
  return out
end

-- The value that applies to a note in layoutId and block instance: only entries for that layout or every layout,
-- and that instance or any, count, and the more specific wins (the layout first). Then whether nothing applied but
-- an entry for that layout and another block instance.
local function pick(entries, property, layoutId, instance)
  local best, bestRank, elsewhere
  for _, e in ipairs(entries) do
    if e.property == property and (e.layout == layoutId or e.layout == -1) then
      if e.instance == instance or e.instance == -1 then
        local rank = (e.layout == layoutId and 2 or 0) + (e.instance == instance and 1 or 0)
        if not bestRank or rank > bestRank then best, bestRank = e.value, rank end
      else
        elsewhere = true
      end
    end
  end
  return best, elsewhere == true and bestRank == nil
end

-- The notehead set id that applies, the default set when none does, and whether the only one set for the layout
-- is another block instance's.
function noteprops.head(entries, layoutId, instance)
  local value, elsewhere = pick(entries, "kNoteheadSetOverride", layoutId, instance)
  if value == nil or value == "" then return constants.DEFAULT_HEAD, elsewhere end
  return value, elsewhere
end

-- The colour that applies as "#rrggbb", or "", and whether the only one set for the layout is another block
-- instance's. Lua writes "#rrggbb"; a command, "#aarrggbb".
function noteprops.colour(entries, layoutId, instance)
  local value, elsewhere = pick(entries, "kEventColour", layoutId, instance)
  local hex = tostring(value or ""):match("^#(%x+)$")
  if hex and (#hex == 6 or #hex == 8) then return "#" .. hex:sub(-6):lower(), elsewhere end
  return "", elsewhere
end

return noteprops
