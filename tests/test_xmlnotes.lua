-- Pairing a MusicXML export with the score's own notes, and taking from it the noteheads (and colours) Lua couldn't
-- read. The dumps say which notes a flow has; a file pairs with a flow when, player by player, its parts hold
-- exactly those notes (by position, sounding pitch and grace).
local bellname = require("hbuc.bellname")
local xmlnotes = require("hbuc.xmlnotes")

local function dumped(flowId, instrument, spelling, pos, grace)
  return { flowId = flowId, instrument = instrument, spelling = spelling, pos = pos, grace = grace or false }
end

-- extra: fields to set, such as headUnreadable or head
local function read(flowId, instrument, spelling, pos, extra)
  local n = { flowId = flowId, instrument = instrument, spelling = spelling, pos = pos, grace = false, head = "",
    colour = "", headUnreadable = false, colourUnreadable = false }
  for k, v in pairs(extra or {}) do n[k] = v end
  return n
end

-- notes: {{spelling, pos, head = ..., filled = ..., colour = ..., grace = ...}}
local function part(name, notes)
  local out = {}
  for _, n in ipairs(notes) do
    local p = bellname.fromSpelling(n[1])
    out[#out + 1] = { pitch = p.pitch, diatonic = p.diatonic, pos = n[2], grace = n.grace or false, head = n.head,
      filled = n.filled, colour = n.colour or "" }
  end
  return { name = name, notes = out }
end

local function file(...)
  return { parts = { ... } }
end

-- A flow (id 4) with bells and chimes on two players, as Goodbye Blue Sky has them.
local FLOW = {
  dumped("4", "Piano 1", "C5", 0), dumped("4", "Piano 1", "E5", 1),
  dumped("4", "Piano 2", "G5", 0),
}
local EXPORT = file(
  part("Piano", { { "C5", 0 }, { "E5", 1, head = "diamond", colour = "#c80000" } }),
  part("Piano", { { "G5", 0 } }))

return {
  only_unreadable_heads_need_a_file = function(t)
    local r = {
      read("3", "A", "C5", 0, { colourUnreadable = true }),
      read("4", "A", "C5", 0, { headUnreadable = true }),
      read("4", "A", "D5", 1, { headUnreadable = true }),
      read("5", "A", "C5", 0),
    }
    t:eq(table.concat(xmlnotes.flowsNeeding(r), ","), "4")
    t:eq(#xmlnotes.flowsNeeding({ read("3", "A", "C5", 0, { colourUnreadable = true }) }), 0,
      "an unreadable colour alone asks for nothing")
  end,
  parts_pair_by_content_not_name = function(t)
    local pairing = xmlnotes.pair(FLOW, EXPORT)
    t:ok(pairing, "paired")
    t:eq(pairing["Piano 1"], 1)
    t:eq(pairing["Piano 2"], 2)
  end,
  a_part_file_does_not_pair = function(t)
    t:eq(xmlnotes.pair(FLOW, file(part("Piano", { { "C5", 0 }, { "E5", 1 } }))), nil)
  end,
  a_different_note_does_not_pair = function(t)
    t:eq(xmlnotes.pair(FLOW, file(part("A", { { "C5", 0 }, { "E5", 2 } }), part("B", { { "G5", 0 } }))), nil,
      "a note moved")
    t:eq(xmlnotes.pair(FLOW, file(part("A", { { "C5", 0 }, { "Fb5", 1 } }), part("B", { { "G5", 0 } }))), nil,
      "the same key, spelled another way")
  end,
  identical_parts_pair_in_order = function(t)
    local flow = { dumped("1", "A", "C5", 0), dumped("1", "B", "C5", 0) }
    local pairing = xmlnotes.pair(flow, file(part("x", { { "C5", 0 } }), part("y", { { "C5", 0 } })))
    t:eq(pairing.A, 1)
    t:eq(pairing.B, 2)
  end,
  parts_with_no_notes_are_ignored = function(t)
    local pairing = xmlnotes.pair(FLOW, file(part("Empty", {}), EXPORT.parts[1], EXPORT.parts[2]))
    t:eq(pairing["Piano 1"], 2)
    t:eq(pairing["Piano 2"], 3)
  end,
  positions_compare_to_a_thousandth = function(t)
    local flow = { dumped("1", "A", "C5", 1 / 3) }
    t:ok(xmlnotes.pair(flow, file(part("A", { { "C5", 0.33333333 } }))), "the dump's 1/3 and the file's")
  end,
  unreadable_heads_take_the_files = function(t)
    local r = {
      read("4", "Piano 1", "C5", 0, { head = "noteheadset.rectangular" }),
      read("4", "Piano 1", "E5", 1, { headUnreadable = true }),
      read("4", "Piano 2", "G5", 0),
    }
    local newRead, missing = xmlnotes.apply(FLOW, r, { EXPORT })
    t:eq(#missing, 0)
    t:eq(newRead[1].head, "noteheadset.rectangular", "a head Lua read is kept")
    t:eq(newRead[2].head, "noteheadset.diamondNoteheads")
    t:eq(newRead[2].headUnreadable, false)
    t:eq(newRead[3].head, "", "a plain note is left alone")
    t:eq(r[2].head, "", "the read list itself is not changed")
  end,
  a_head_the_file_lost_is_not_in_musicxml = function(t)
    local r = { read("4", "Piano 1", "C5", 0, { headUnreadable = true }) }
    local newRead = xmlnotes.apply(FLOW, r, { EXPORT })
    t:eq(newRead[1].head, "noteheadset.notInMusicXML")
  end,
  unreadable_colours_take_the_files = function(t)
    local r = {
      read("4", "Piano 1", "E5", 1, { headUnreadable = true, colourUnreadable = true }),
      read("4", "Piano 1", "C5", 0, { colourUnreadable = true }),
    }
    local newRead = xmlnotes.apply(FLOW, r, { EXPORT })
    t:eq(newRead[1].colour, "#c80000")
    t:eq(newRead[1].colourUnreadable, false)
    t:eq(newRead[2].colour, "", "the file has no colour for it either")
    t:eq(newRead[2].colourUnreadable, true)
  end,
  extra_files_are_ignored_and_missing_flows_reported = function(t)
    local d = { FLOW[1], FLOW[2], FLOW[3], dumped("7", "Piano 1", "D5", 0) }
    local r = { read("4", "Piano 1", "E5", 1, { headUnreadable = true }),
      read("7", "Piano 1", "D5", 0, { headUnreadable = true }) }
    local other = file(part("Flute", { { "A5", 0 } }))
    local partFile = file(EXPORT.parts[1])
    local newRead, missing, paired = xmlnotes.apply(d, r, { other, partFile, EXPORT })
    t:eq(newRead[1].head, "noteheadset.diamondNoteheads", "flow 4 paired with the third file")
    t:eq(table.concat(paired, ","), "4")
    t:eq(table.concat(missing, ","), "7")
    -- Dorico's export can leave a flow out (Goodbye Blue Sky's hand-made chart flow): its changed heads are still
    -- kept apart from plain ones
    t:eq(newRead[2].head, "noteheadset.notInMusicXML", "flow 7's changed head")
    t:eq(newRead[2].headUnreadable, false)
  end,
  no_file_pairs_with_any_flow = function(t)
    local r = { read("4", "Piano 1", "E5", 1, { headUnreadable = true }) }
    local _, missing, paired = xmlnotes.apply(FLOW, r, { file(EXPORT.parts[1]) })
    t:eq(#paired, 0)
    t:eq(table.concat(missing, ","), "4")
  end,
  a_unison_merged_by_the_paste_still_pairs = function(t)
    local d = { dumped("1", "A", "C5", 0), dumped("1", "A", "C5", 0) }
    local r = { read("1", "A", "C5", 0, { headUnreadable = true }) }
    local newRead, missing = xmlnotes.apply(d, r,
      { file(part("A", { { "C5", 0 }, { "C5", 0, head = "diamond" } })) })
    t:eq(#missing, 0)
    t:eq(newRead[1].head, "noteheadset.diamondNoteheads", "a changed note takes the file's changed head first")
  end,
  grace_notes_pair_as_grace_notes = function(t)
    local d = { dumped("1", "A", "B5", 2, true), dumped("1", "A", "C6", 2) }
    t:ok(xmlnotes.pair(d, file(part("A", { { "B5", 2, grace = true }, { "C6", 2 } }))), "paired")
    t:eq(xmlnotes.pair(d, file(part("A", { { "B5", 2 }, { "C6", 2 } }))), nil, "not with a plain note")
  end,
}
