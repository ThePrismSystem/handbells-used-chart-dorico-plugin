-- The question about notehead sets of one shape when one of them is rare (fewer than combine.FEWEST notes): an
-- arranger who picked Old-Style Diamond for one chime among 435 Diamonds most likely meant them to chart together.
local combine = require("hbuc.combine")
local constants = require("hbuc.constants")

local D = constants.DIALOG
local DIAMOND, OLD, WHITE, WIDE = "noteheadset.diamondNoteheads", "noteheadset.oldDiamondNoteheads",
  "noteheadset.whiteDiamondNoteheads", "noteheadset.wideDiamondNoteheads"

-- records with these heads, as {id, count} pairs in order
local function records(...)
  local out = {}
  for _, pair in ipairs({ ... }) do
    for _ = 1, pair[2] do out[#out + 1] = { head = pair[1], instrument = "A" } end
  end
  return out
end

local function ids(group)
  local out = {}
  for i, h in ipairs(group.heads) do out[i] = h.id .. "=" .. h.count end
  return table.concat(out, ",")
end

return {
  a_rare_diamond_with_common_ones = function(t)
    local groups = combine.groups(records({ DIAMOND, 435 }, { OLD, 1 }))
    t:eq(#groups, 1)
    t:eq(groups[1].shape, "Diamond")
    t:eq(ids(groups[1]), DIAMOND .. "=435," .. OLD .. "=1")
    t:eq(groups[1].into, DIAMOND, "the set with the most notes")
  end,
  five_notes_is_not_rare = function(t)
    t:eq(combine.FEWEST, 5)
    t:eq(#combine.groups(records({ DIAMOND, 7 }, { OLD, 5 })), 0)
    t:eq(#combine.groups(records({ DIAMOND, 7 }, { OLD, 4 })), 1)
  end,
  different_shapes_never_group = function(t)
    t:eq(#combine.groups(records({ DIAMOND, 1 }, { "noteheadset.rectangular", 1 })), 0)
  end,
  sets_with_no_chart_shape_never_group = function(t)
    t:eq(#combine.groups(records({ "noteheadset.Xnoteheads", 1 }, { "noteheadset.circleXNoteheads", 50 })), 0)
  end,
  one_set_alone_is_no_question = function(t)
    t:eq(#combine.groups(records({ OLD, 1 })), 0)
  end,
  three_sets_listed_by_count = function(t)
    local groups = combine.groups(records({ WHITE, 2 }, { DIAMOND, 10 }, { WIDE, 3 }))
    t:eq(ids(groups[1]), DIAMOND .. "=10," .. WIDE .. "=3," .. WHITE .. "=2")
  end,
  a_tie_keeps_the_first_seen = function(t)
    local groups = combine.groups(records({ OLD, 3 }, { DIAMOND, 3 }))
    t:eq(ids(groups[1]), OLD .. "=3," .. DIAMOND .. "=3")
    t:eq(groups[1].into, OLD)
  end,
  round_sets_group_too = function(t)
    local groups = combine.groups(records({ "noteheadset.default", 100 }, { "noteheadset.large", 2 }))
    t:eq(groups[1].shape, "Round")
    t:eq(groups[1].into, "noteheadset.default")
  end,
  groups_come_in_shape_order = function(t)
    -- a custom set is read by its name, which here is its id
    local groups = combine.groups(records({ "noteheadset.rectangular", 10 }, { "custom.square", 1 }, { DIAMOND, 10 },
      { OLD, 1 }))
    t:eq(#groups, 2)
    t:eq(groups[1].shape, "Diamond")
    t:eq(groups[2].shape, "Square")
  end,
  the_question = function(t)
    local q = combine.question(combine.groups(records({ DIAMOND, 435 }, { OLD, 1 }))[1])
    t:eq(q.title, D.resultsTitle)
    t:eq(q.text, "The music uses more than one diamond notehead:\n\nDiamond Noteheads: 435 notes\n"
      .. "Old-Style Diamond Noteheads: 1 note\n\nCombine them all as Diamond Noteheads, or keep them separate?")
    t:eq(#q.buttons, 2)
    t:eq(q.buttons[1].id, "combine")
    t:eq(q.buttons[1].label, "Combine")
    t:eq(q.buttons[2].id, "separate")
    t:eq(q.buttons[2].label, D.keepSeparate)
    t:eq(q.cancel, "separate", "closing the window keeps them separate")
  end,
  apply_moves_the_group_to_one_set = function(t)
    local recs = records({ DIAMOND, 2 }, { OLD, 1 }, { "noteheadset.default", 1 })
    combine.apply(recs, combine.groups(recs)[1])
    t:eq(recs[3].head, DIAMOND, "the old-style diamond")
    t:eq(recs[4].head, "noteheadset.default", "another shape stays")
  end,
}
