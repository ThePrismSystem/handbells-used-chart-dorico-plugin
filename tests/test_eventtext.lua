-- Dorico event tostring() parsing, from spike/lib/test_events.lua plus later fixes.
local eventtext = require("hbuc.eventtext")

return {
  notes = function(t)
    local n = eventtext.parse("kNoteEvent (id:195) at 4, duration 1  G#5 (ends 5)")
    t:eq(n.kind, "note")
    t:eq(n.id, 195)
    t:eq(n.pos, 4)
    t:eq(n.spelling, "G#5")
    t:eq(n.name, "G#")
    t:eq(n.octave, 5)
    local f = eventtext.parse("kNoteEvent (id:981) at 13/2 (6.5), duration 1/2 (0.5)  Bb4 (ends 7)")
    t:eq(f.pos, 6.5, "fraction position")
    t:eq(f.name, "Bb")
  end,
  grace_notes = function(t)
    local g = eventtext.parse("kGraceNoteEvent (id:200) at 8  secondary pos -1/2 (-0.5), notated duration: 1/2 (0.5), B6 ")
    t:eq(g.kind, "grace")
    t:eq(g.pos, 8)
    t:eq(g.spelling, "B6")
  end,
  other_kinds = function(t)
    t:eq(eventtext.parse("kNoteEvent (id:228) at 13, duration 1  B-1 (ends 14)").octave, -1, "negative octave")
    local r = eventtext.parse("kRestEvent (id:216) at 0, duration 1 ")
    t:eq(r.kind, "rest")
    t:eq(r.spelling, nil)
    t:eq(eventtext.parse("kBarRestEvent (id:282) at 0, duration 4 ").kind, "rest")
    local x = eventtext.parse("kTextEvent (id:317) at 0 : HBUCMARK10\n (paragraph.defaulttext)")
    t:eq(x.kind, "text")
    t:eq(x.text, "HBUCMARK10")
    t:eq(eventtext.parse("kClefEvent (id:185) at 0 \nClef entity ID").kind, "other")
    t:eq(eventtext.parse("kBarDivisionEvent (id:334) at 4  element ID = 0").kind, "bardivision")
    t:eq(eventtext.parse("kBreakEvent (id:335) at 4 ").kind, "break")
  end,
  exact_fraction = function(t)
    local e = eventtext.parse("kNoteEvent (id:1) at 1/3 (0.333333), duration 1/3 (0.333333)  C4 (ends 2/3 (0.666667))")
    t:eq(e.pos, 1 / 3, "the exact fraction wins over the rounded decimal")
  end,
  double_sharp_and_flat = function(t)
    local e = eventtext.parse("kNoteEvent (id:2) at 0, duration 1  Fx4 (ends 1)")
    t:eq(e.name, "Fx")
    t:eq(e.spelling, "Fx4")
    t:eq(eventtext.parse("kNoteEvent (id:3) at 0, duration 1  Ebb4 (ends 1)").name, "Ebb")
  end,
}
