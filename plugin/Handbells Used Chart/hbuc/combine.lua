-- Notehead sets of one chart shape where one of them is rare. A handful of notes in a second diamond set beside
-- hundreds of Diamonds is most likely a stray choice, and left alone it gets a notehead entry, and a dialog choice,
-- of its own. The user is asked whether to combine them.
local constants = require("hbuc.constants")
local shapes = require("hbuc.shapes")

local combine = {}

local M, D = constants.MESSAGES, constants.DIALOG

-- A set with fewer notes than this, beside another of its shape, is asked about.
combine.FEWEST = 5

-- {{shape, heads = {{id, count}} (most notes first, ties in first-seen order), into = the first's id}}, one per
-- chart shape that two or more sets share when one of them has fewer than FEWEST notes, in constants.SHAPES order.
function combine.groups(records)
  local counts, order = {}, {}
  for _, r in ipairs(records) do
    local id = r.head
    if not counts[id] then
      counts[id] = 0
      order[#order + 1] = id
    end
    counts[id] = counts[id] + 1
  end
  local byShape = {}
  for rank, id in ipairs(order) do
    local shape = shapes.ofNoteheadSet(id, shapes.displayName(id))
    if shape ~= "" then
      byShape[shape] = byShape[shape] or {}
      table.insert(byShape[shape], { id = id, count = counts[id], rank = rank })
    end
  end
  local groups = {}
  for _, shape in ipairs(constants.SHAPES) do
    local heads = byShape[shape]
    if heads and #heads > 1 then
      table.sort(heads, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.rank < b.rank
      end)
      if heads[#heads].count < combine.FEWEST then
        groups[#groups + 1] = { shape = shape, heads = heads, into = heads[1].id }
      end
    end
  end
  return groups
end

-- The choice message for one group (ctx.choose).
function combine.question(group)
  local lines = {}
  for i, h in ipairs(group.heads) do
    local name = shapes.displayName(h.id)
    lines[i] = h.count == 1 and string.format(M.combineOneNote, name) or string.format(M.combineNotes, name, h.count)
  end
  return {
    title = D.resultsTitle,
    text = string.format(M.combineNoteheads, group.shape:lower(), table.concat(lines, "\n"),
      shapes.displayName(group.into)),
    buttons = { { id = "combine", label = D.combine }, { id = "separate", label = D.keepSeparate } },
    cancel = "separate",
  }
end

-- Gives every record of the group's sets the set it combines into.
function combine.apply(records, group)
  local member = {}
  for _, h in ipairs(group.heads) do member[h.id] = true end
  for _, r in ipairs(records) do
    if member[r.head] then r.head = group.into end
  end
end

return combine
