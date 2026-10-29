-- Pairing a MusicXML export with the score's own notes, and taking from it the noteheads (and colours) Lua couldn't
-- read. The dumps say which notes a flow has; a file pairs with a flow when, for each player whose noteheads need it,
-- a part holds exactly that player's notes (by position, sounding pitch and grace).
local bellname = require("hbuc.bellname")
local constants = require("hbuc.constants")
local shapes = require("hbuc.shapes")
local xmlnotes = require("hbuc.xmlnotes")

local M, D = constants.MESSAGES, constants.DIALOG
local DIAMOND, PLAIN = "noteheadset.diamondNoteheads", "noteheadset.default"

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

-- notes: {{spelling, pos, head = ..., filled = ..., colour = ..., grace = ..., bar = ..., written = ...}}
local function part(name, notes)
  local out = {}
  for _, n in ipairs(notes) do
    local p = bellname.fromSpelling(n[1])
    out[#out + 1] = { pitch = p.pitch, diatonic = p.diatonic, pos = n[2], grace = n.grace or false, head = n.head,
      filled = n.filled, colour = n.colour or "", bar = n.bar, written = n.written }
  end
  return { name = name, notes = out }
end

local function buttonIds(choice)
  local out = {}
  for _, b in ipairs(choice.buttons) do out[#out + 1] = b.id end
  return table.concat(out, ",")
end

-- A read note apply named as not in MusicXML, with what the file said of it (bar and written pitch), if anything.
local function unnamed(flowId, instrument, spelling, pos, bar, written)
  return read(flowId, instrument, spelling, pos, { head = shapes.NOT_IN_MUSICXML, bar = bar, written = written })
end

local function file(...)
  return { parts = { ... } }
end

-- A flow (id 4) with bells and chimes on two players who share a name.
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
    -- Dorico's export can leave a flow out (one holding a hand-made chart): its changed heads are still kept apart
    -- from plain ones
    t:eq(newRead[2].head, "noteheadset.notInMusicXML", "flow 7's changed head")
    t:eq(newRead[2].headUnreadable, false)
  end,
  no_file_pairs_with_any_flow = function(t)
    -- another player's part (or another piece): the changed notes' player isn't in it
    local r = { read("4", "Piano 1", "E5", 1, { headUnreadable = true }) }
    local _, missing, paired = xmlnotes.apply(FLOW, r, { file(EXPORT.parts[2]) })
    t:eq(#paired, 0)
    t:eq(table.concat(missing, ","), "4")
  end,
  only_players_with_changed_notes_need_to_pair = function(t)
    -- a player whose notes the file can't hold (unpitched percussion, which the reader skips) doesn't stop the
    -- handbells taking their noteheads from it
    local d = { FLOW[1], FLOW[2], FLOW[3], dumped("4", "Drums", "C4", 0) }
    local r = { read("4", "Piano 1", "E5", 1, { headUnreadable = true }), read("4", "Drums", "C4", 0) }
    local newRead, missing, paired = xmlnotes.apply(d, r, { EXPORT })
    t:eq(#missing, 0)
    t:eq(table.concat(paired, ","), "4")
    t:eq(newRead[1].head, "noteheadset.diamondNoteheads")
  end,
  a_player_with_only_unreadable_colours_need_not_pair = function(t)
    -- notes coloured in the Properties panel on a player the file can't hold (unpitched percussion)
    local d = { FLOW[1], FLOW[2], FLOW[3], dumped("4", "Drums", "C4", 0) }
    local r = { read("4", "Piano 1", "E5", 1, { headUnreadable = true }),
      read("4", "Drums", "C4", 0, { colourUnreadable = true }) }
    local newRead, missing = xmlnotes.apply(d, r, { EXPORT })
    t:eq(#missing, 0)
    t:eq(newRead[1].head, "noteheadset.diamondNoteheads")
    t:eq(newRead[2].colourUnreadable, true, "no part of its own, so its colour stays unread")
  end,
  a_player_with_only_unreadable_colours_takes_them_from_its_part = function(t)
    local r = { read("4", "Piano 1", "E5", 1, { headUnreadable = true }),
      read("4", "Piano 2", "G5", 0, { colourUnreadable = true }) }
    local export = file(EXPORT.parts[1], part("Piano", { { "G5", 0, colour = "#008000" } }))
    local newRead, missing = xmlnotes.apply(FLOW, r, { export })
    t:eq(#missing, 0)
    t:eq(newRead[2].colour, "#008000")
    t:eq(newRead[2].colourUnreadable, false)
    t:eq(newRead[2].head, "", "its head was read, and stays")
  end,
  a_doubling_player_takes_the_part_named_after_it = function(t)
    -- B plays A's notes with plain heads, and comes first in the file: A's heads are in its own part
    local d = { dumped("1", "A", "C5", 0), dumped("1", "B", "C5", 0) }
    local r = { read("1", "A", "C5", 0, { headUnreadable = true }), read("1", "B", "C5", 0) }
    local newRead, missing = xmlnotes.apply(d, r,
      { file(part("B", { { "C5", 0 } }), part("A", { { "C5", 0, head = "diamond" } })) })
    t:eq(#missing, 0)
    t:eq(newRead[1].head, "noteheadset.diamondNoteheads")
  end,
  a_file_pairs_with_one_flow_only = function(t)
    -- each flow has a file of its own, so two flows with the same notes don't share one
    local d = { dumped("1", "A", "C5", 0), dumped("2", "A", "C5", 0) }
    local r = { read("1", "A", "C5", 0, { headUnreadable = true }), read("2", "A", "C5", 0, { headUnreadable = true }) }
    local newRead, missing, paired = xmlnotes.apply(d, r, { file(part("A", { { "C5", 0, head = "diamond" } })) })
    t:eq(table.concat(paired, ","), "1")
    t:eq(table.concat(missing, ","), "2")
    t:eq(newRead[2].head, "noteheadset.notInMusicXML")
  end,
  a_changed_note_the_file_lacks_is_not_in_musicxml = function(t)
    -- the file pairs, but holds no note where the read found this one: never the default head, and counted
    local d = { dumped("1", "A", "C5", 0) }
    local r = { read("1", "A", "C5", 0, { headUnreadable = true }), read("1", "A", "D5", 5, { headUnreadable = true }) }
    local newRead, _, _, unmatched = xmlnotes.apply(d, r, { file(part("A", { { "C5", 0, head = "diamond" } })) })
    t:eq(newRead[1].head, "noteheadset.diamondNoteheads")
    t:eq(newRead[2].head, "noteheadset.notInMusicXML")
    t:eq(newRead[2].headUnreadable, false)
    t:eq(unmatched, 1)
    t:eq(select(4, xmlnotes.apply(FLOW, { read("4", "Piano 1", "E5", 1, { headUnreadable = true }) }, { EXPORT })), 0,
      "none when every changed note is in the file")
  end,
  a_unison_merged_by_the_paste_still_pairs = function(t)
    local d = { dumped("1", "A", "C5", 0), dumped("1", "A", "C5", 0) }
    local r = { read("1", "A", "C5", 0, { headUnreadable = true }) }
    local newRead, missing = xmlnotes.apply(d, r,
      { file(part("A", { { "C5", 0 }, { "C5", 0, head = "diamond" } })) })
    t:eq(#missing, 0)
    t:eq(newRead[1].head, "noteheadset.diamondNoteheads", "a changed note takes the file's changed head first")
  end,
  a_head_from_the_file_brings_its_bar_and_written_pitch = function(t)
    local r = { read("4", "Piano 1", "E5", 1, { headUnreadable = true }) }
    local export = file(part("Piano", { { "C5", 0 }, { "E5", 1, bar = "32", written = "E4" } }), EXPORT.parts[2])
    local newRead = xmlnotes.apply(FLOW, r, { export })
    t:eq(newRead[1].bar, "32")
    t:eq(newRead[1].written, "E4", "as the score shows it")
  end,
  one_unnamed_note_and_one_other_notehead = function(t)
    local r = { read("4", "Piano 1", "C5", 0, { head = DIAMOND }), unnamed("4", "Piano 1", "C#4", 127.5, "32", "C#4") }
    local q = xmlnotes.groupQuestion(r, { DIAMOND, shapes.NOT_IN_MUSICXML })
    t:eq(q.title, D.resultsTitle)
    t:eq(q.text, string.format(M.musicxmlUnnamedNote, "C#4 in bar 32") .. "\n\n"
      .. string.format(M.musicxmlGroupWithOne, "Diamond Noteheads", constants.NOT_IN_MUSICXML_NAME))
    t:eq(buttonIds(q), DIAMOND .. ",separate")
    t:eq(q.buttons[1].label, string.format(D.includeWith, "Diamond Noteheads"))
    t:eq(q.buttons[2].label, D.keepSeparate)
    t:eq(q.cancel, "separate", "closing the window keeps them separate")
  end,
  several_unnamed_notes_and_several_noteheads = function(t)
    -- in the music's order; the player named when there are two; just the pitch Lua has when the file had no note
    local r = {
      unnamed("4", "Piano 1", "D5", 40, "11", "D4"),
      read("4", "Piano 1", "C5", 0),
      unnamed("4", "Piano 2", "E5", 8),
      unnamed("4", "Piano 1", "C#4", 2, "1", "C#4"),
    }
    local q = xmlnotes.groupQuestion(r, { PLAIN, shapes.NOT_IN_MUSICXML, DIAMOND })
    t:eq(q.text, string.format(M.musicxmlUnnamedNotes, 3, "C#4 in bar 1 (Piano 1), E5 (Piano 2), D4 in bar 11 (Piano 1)")
      .. "\n\n" .. string.format(M.musicxmlGroupChooseMany, constants.NOT_IN_MUSICXML_NAME))
    t:eq(buttonIds(q), PLAIN .. "," .. DIAMOND .. ",separate")
    t:eq(q.buttons[1].label, "Default Noteheads", "named as the options dialog names them")
    t:eq(q.buttons[2].label, "Diamond Noteheads")
  end,
  the_wording_follows_the_counts = function(t)
    local one = xmlnotes.groupQuestion({ unnamed("1", "A", "C5", 0, "2", "C4") }, { PLAIN, DIAMOND })
    t:eq(one.text, string.format(M.musicxmlUnnamedNote, "C4 in bar 2") .. "\n\n"
      .. string.format(M.musicxmlGroupChooseOne, constants.NOT_IN_MUSICXML_NAME))
    local two = xmlnotes.groupQuestion({ unnamed("1", "A", "C5", 0, "2", "C4"), unnamed("1", "A", "D5", 1, "2", "D4") },
      { DIAMOND })
    t:eq(two.text, string.format(M.musicxmlUnnamedNotes, 2, "C4 in bar 2, D4 in bar 2") .. "\n\n"
      .. string.format(M.musicxmlGroupWithMany, "Diamond Noteheads", constants.NOT_IN_MUSICXML_NAME))
  end,
  nothing_is_asked_without_a_few_unnamed_notes_and_another_notehead = function(t)
    t:eq(xmlnotes.groupQuestion({ read("1", "A", "C5", 0) }, { PLAIN }), nil, "none unnamed")
    local five = {}
    for i = 1, 5 do five[i] = unnamed("1", "A", "C5", i) end
    t:eq(xmlnotes.groupQuestion(five, { PLAIN, shapes.NOT_IN_MUSICXML }), nil, "five or more are the score's own choice")
    local four = { five[1], five[2], five[3], five[4] }
    t:ok(xmlnotes.groupQuestion(four, { PLAIN, shapes.NOT_IN_MUSICXML }), "four are asked about")
    t:eq(xmlnotes.groupQuestion({ unnamed("1", "A", "C5", 0) }, { shapes.NOT_IN_MUSICXML }), nil, "nothing to offer")
  end,
  grouping_gives_the_unnamed_notes_the_chosen_head = function(t)
    local r = { read("1", "A", "C5", 0, { head = DIAMOND }), unnamed("1", "A", "D5", 1), read("1", "A", "E5", 2) }
    xmlnotes.group(r, DIAMOND)
    t:eq(r[2].head, DIAMOND)
    t:eq(r[3].head, "", "a plain note is left alone")
  end,
  grace_notes_pair_as_grace_notes = function(t)
    local d = { dumped("1", "A", "B5", 2, true), dumped("1", "A", "C6", 2) }
    t:ok(xmlnotes.pair(d, file(part("A", { { "B5", 2, grace = true }, { "C6", 2 } }))), "paired")
    t:eq(xmlnotes.pair(d, file(part("A", { { "B5", 2 }, { "C6", 2 } }))), nil, "not with a plain note")
  end,
}
