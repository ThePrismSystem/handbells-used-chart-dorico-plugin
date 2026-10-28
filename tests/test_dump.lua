-- stream:dump() text, the only view of a voice stream that works on real music (lyrics, slurs and playing
-- techniques make stream.events throw). Lines are copied from dumps of the fixture and the Smith example.
local dump = require("hbuc.dump")

local RULE = "------------------------------"

local function lines(list)
  return table.concat(list, "\n") .. "\n"
end

return {
  parses_notes_and_grace_notes = function(t)
    local d = dump.parse(lines({
      RULE,
      "Start block id: 1010 position: 0",
      "16 (16) dur: 1: kNoteEvent (id:209) at 16, duration 1  C5 (ends 17)",
      "8 (8): kGraceNoteEvent (id:200) at 8  secondary pos -1/2 (-0.5), notated duration: 1/2 (0.5), B6 ",
    }))
    local notes = dump.notes(d)
    t:eq(#notes, 2)
    t:eq(notes[1].spelling, "C5")
    t:eq(notes[1].grace, false)
    t:eq(notes[1].id, 209)
    t:eq(notes[2].spelling, "B6")
    t:eq(notes[2].grace, true)
    t:eq(notes[2].id, 200)
  end,
  fractional_positions_in_the_prefix = function(t)
    local d = dump.parse(lines({
      RULE,
      "1.5 (3/2 (1.5)) dur: 1/2 (0.5): kNoteEvent (id:2884) at 3/2 (1.5), duration 1/2 (0.5)  Eb4 (ends 2)",
    }))
    t:eq(#d.events, 1)
    t:eq(d.events[1].id, 2884)
    t:eq(d.events[1].pos, 1.5)
    t:eq(dump.notes(d)[1].spelling, "Eb4")
  end,
  events_carry_their_block_instance = function(t)
    -- "Start block id" is a block instance id. EventEdit.Select takes a block id, which the dump doesn't show: in one
    -- downloaded project instance 1061 held block 36 (hbuc.dorico.doc.blockIdOf reads it).
    local d = dump.parse(lines({
      RULE,
      "Start block id: 1061 position: 0",
      "0 (0) dur: 1: kNoteEvent (id:7932) at 0, duration 1  E5 (ends 1)",
      "Start block id: 1070 position: 16",
      "16 (16) dur: 1: kNoteEvent (id:8000) at 16, duration 1  C6 (ends 17)",
    }))
    t:eq(d.events[1].instance, 1061)
    t:eq(d.events[2].instance, 1070)
    t:eq(d.blockId, nil, "no block id is guessed from the instance id")
  end,
  first_event_gives_its_instance = function(t)
    local d = dump.parse(lines({
      RULE,
      "Start block id: 1061 position: 0",
      "0 (0) dur: 1: kNoteEvent (id:7932) at 0, duration 1  E5 (ends 1)",
    }))
    local id, instance = dump.firstEventId(d)
    t:eq(id, 7932)
    t:eq(instance, 1061)
  end,
  text_ends_before_its_paragraph_style = function(t)
    local d = dump.parse(lines({
      RULE,
      "0 (0): kTextEvent (id:2740) at 0 : CANTOR",
      " (paragraph.defaulttext)",
      "0 (0): kTextEvent (id:2781) at 0 : HBUC|1|7,8|1|bells,7,5|kAlwaysInsertHeadings|kNever||",
      " (paragraph.defaulttext)",
    }))
    t:eq(#d.events, 2)
    t:eq(d.events[1].kind, "text")
    t:eq(d.events[1].text, "CANTOR")
    t:eq(d.events[2].text, "HBUC|1|7,8|1|bells,7,5|kAlwaysInsertHeadings|kNever||")
  end,
  multi_line_text_keeps_its_lines = function(t)
    local d = dump.parse(lines({
      RULE,
      "0 (0): kTextEvent (id:5) at 0 : first line",
      "second line",
      " (paragraph.defaulttext)",
      "1 (1) dur: 1: kNoteEvent (id:6) at 1, duration 1  D5 (ends 2)",
    }))
    t:eq(#d.events, 2)
    t:eq(d.events[1].text, "first line\nsecond line")
    t:eq(d.events[2].kind, "note")
  end,
  lyrics_are_other = function(t)
    local d = dump.parse(lines({
      RULE,
      "0 (0) dur: 8: kNoteEvent (id:2) at 0, duration 8  Ab3 (ends 8)",
      "0 (0): kLyricEvent (id:3) at 0  element ID = 0,  duration 0",
    }))
    t:eq(#d.events, 2)
    t:eq(d.events[2].kind, "other")
    t:eq(#dump.notes(d), 1)
  end,
  first_event_skips_texts = function(t)
    local d = dump.parse(lines({
      RULE,
      "0 (0): kTextEvent (id:2735) at 0 : SOPRANO",
      " (paragraph.defaulttext)",
      "0 (0) dur: 1: kRestEvent (id:216) at 0, duration 1  ",
      "11 (11) dur: 1: kNoteEvent (id:226) at 11, duration 1  G3 (ends 12)",
    }))
    t:eq(dump.firstEventId(d), 216)
  end,
  empty_dump = function(t)
    local d = dump.parse(RULE .. "\n")
    t:eq(d.blockId, nil)
    t:eq(#d.events, 0)
    t:eq(dump.firstEventId(d), nil)
  end,
}
