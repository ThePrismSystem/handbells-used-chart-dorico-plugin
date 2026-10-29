-- MusicXML as Dorico exports it, read into notes: sounding pitch, position in quarters from the flow's start,
-- notehead and colour. The position rules matched Dorico's dumps note for note on the fixture and on Liszt
-- (spike/49_positions.py).
local musicxml = require("hbuc.musicxml")

local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"

local HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n'
  .. '<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN"'
  .. ' "http://www.musicxml.org/dtds/partwise.dtd">\n'

-- parts: {{name = "...", body = "<measure>...</measure>..."}}
local function score(parts)
  local list, bodies = {}, {}
  for i, p in ipairs(parts) do
    list[#list + 1] = string.format('<score-part id="P%d"><part-name>%s</part-name></score-part>', i, p.name)
    bodies[#bodies + 1] = string.format('<part id="P%d">%s</part>', i, p.body)
  end
  return HEAD .. '<score-partwise version="4.0"><part-list>' .. table.concat(list) .. "</part-list>"
    .. table.concat(bodies) .. "</score-partwise>"
end

-- n = {step, octave, duration, alter, before = xml before <pitch>, after = xml after <duration>, attrs = " a=..."}
local function note(n)
  return string.format("<note%s>%s<pitch><step>%s</step>%s<octave>%d</octave></pitch><duration>%d</duration>%s</note>",
    n.attrs or "", n.before or "", n[1], n.alter and ("<alter>" .. n.alter .. "</alter>") or "", n[2], n[3] or 0,
    n.after or "")
end

local function measure(...)
  return "<measure>" .. table.concat({ ... }) .. "</measure>"
end

local DIVISIONS = "<attributes><divisions>1</divisions></attributes>"

local function near(a, b) return math.abs(a - b) < 1e-9 end

local function only(parts)
  local parsed, err = musicxml.parse(score(parts))
  if not parsed then error("parse failed: " .. tostring(err), 2) end
  return parsed
end

return {
  reads_parts_and_notes = function(t)
    local parsed = only({
      { name = "Handbells (A)", body = measure(DIVISIONS, note({ "C", 4, 1 }), note({ "F", 4, 1, alter = 1 })) },
      { name = "Organ", body = measure(DIVISIONS, note({ "B", 3, 2, alter = -1 })) },
    })
    t:eq(#parsed.parts, 2)
    t:eq(parsed.parts[1].name, "Handbells (A)")
    t:eq(parsed.parts[2].name, "Organ")
    local c4, fs4 = parsed.parts[1].notes[1], parsed.parts[1].notes[2]
    t:eq(c4.pitch, 60)
    t:eq(c4.diatonic, 28)
    t:eq(c4.pos, 0)
    t:eq(c4.grace, false)
    t:eq(fs4.pitch, 66)
    t:eq(fs4.diatonic, 31)
    t:eq(fs4.pos, 1)
    t:eq(parsed.parts[2].notes[1].pitch, 58, "B flat 3")
  end,
  chords_share_an_onset_and_backup_starts_a_voice = function(t)
    local parsed = only({ { name = "P", body = measure(DIVISIONS,
      note({ "C", 4, 2 }), note({ "E", 4, 2, before = "<chord/>" }), note({ "G", 4, 2 }),
      "<backup><duration>4</duration></backup>",
      note({ "C", 3, 1 }), "<forward><duration>2</duration></forward>", note({ "D", 3, 1 }))
      .. measure(note({ "A", 4, 4 })) } })
    local pos = {}
    for _, n in ipairs(parsed.parts[1].notes) do pos[#pos + 1] = n.pos end
    t:eq(table.concat(pos, ","), "0,0,2,0,3,4", "chord, next note, second voice, after a forward, next measure")
  end,
  divisions_and_tuplets_give_quarter_positions = function(t)
    local parsed = only({ { name = "P", body = measure("<attributes><divisions>3</divisions></attributes>",
      note({ "C", 4, 1 }), note({ "D", 4, 1 }), note({ "E", 4, 1 }), note({ "F", 4, 3 })) } })
    local notes = parsed.parts[1].notes
    t:ok(near(notes[2].pos, 1 / 3), "the second triplet eighth")
    t:ok(near(notes[3].pos, 2 / 3), "the third")
    t:ok(near(notes[4].pos, 1), "the quarter after them")
  end,
  grace_notes_sit_at_the_next_notes_onset = function(t)
    local parsed = only({ { name = "P", body = measure(DIVISIONS, note({ "C", 4, 2 }),
      note({ "B", 5, nil, before = "<grace/>" }), note({ "C", 6, 2 })) } })
    local grace, main = parsed.parts[1].notes[2], parsed.parts[1].notes[3]
    t:eq(grace.grace, true)
    t:eq(grace.pos, 2)
    t:eq(main.grace, false)
    t:eq(main.pos, 2)
  end,
  tie_stops_and_cue_notes_are_skipped = function(t)
    local parsed = only({ { name = "P", body = measure(DIVISIONS, note({ "C", 4, 4, after = '<tie type="start"/>' }))
      .. measure(note({ "C", 4, 4, after = '<tie type="stop"/>' }), note({ "D", 4, 1, before = "<cue/>" }))
      .. measure(note({ "E", 4, 4 })) } })
    local notes = parsed.parts[1].notes
    t:eq(#notes, 2, "the tied-over half and the cue note are not notes of their own")
    t:eq(notes[1].pitch, 60)
    t:eq(notes[2].pitch, 64)
    t:eq(notes[2].pos, 9, "the cue note still takes its time")
  end,
  transpose_gives_sounding_pitch_per_staff = function(t)
    local attributes = "<attributes><divisions>1</divisions>"
      .. '<transpose number="1"><diatonic>0</diatonic><chromatic>0</chromatic><octave-change>1</octave-change></transpose>'
      .. '<transpose number="2"><diatonic>0</diatonic><chromatic>0</chromatic><octave-change>1</octave-change></transpose>'
      .. "</attributes>"
    local bb = "<attributes><divisions>1</divisions>"
      .. "<transpose><diatonic>-1</diatonic><chromatic>-2</chromatic></transpose></attributes>"
    local parsed = only({
      { name = "Handbells", body = measure(attributes, note({ "C", 4, 1, after = "<staff>2</staff>" }),
        note({ "D", 5, 1 })) },
      { name = "Clarinet in B flat", body = measure(bb, note({ "D", 4, 1 })) },
    })
    local c, d = parsed.parts[1].notes[1], parsed.parts[1].notes[2]
    t:eq(c.pitch, 72, "written C4 on the second staff sounds C5")
    t:eq(c.diatonic, 35)
    t:eq(d.pitch, 86, "and on the first, D5 sounds D6")
    local clarinet = parsed.parts[2].notes[1]
    t:eq(clarinet.pitch, 60, "a transposition with no number covers every staff: written D4 sounds C4")
    t:eq(clarinet.diatonic, 28)
  end,
  noteheads_and_colours = function(t)
    local parsed = only({ { name = "P", body = measure(DIVISIONS,
      note({ "C", 4, 1, after = '<notehead filled="no">diamond</notehead>' }),
      note({ "D", 4, 1, attrs = ' color="#C80000"', after = "<notehead>inverted triangle</notehead>" }),
      note({ "E", 4, 1, attrs = ' color="#FFC80000"' }),
      note({ "F", 4, 1, after = '<notehead color="#008000">x</notehead>' })) } })
    local n = parsed.parts[1].notes
    t:eq(n[1].head, "diamond")
    t:eq(n[1].filled, false)
    t:eq(n[1].colour, "")
    t:eq(n[2].head, "inverted triangle")
    t:eq(n[2].filled, nil)
    t:eq(n[2].colour, "#c80000", "lower case, as Lua reads a colour")
    t:eq(n[3].head, nil, "no <notehead>")
    t:eq(n[3].colour, "#c80000", "an alpha byte is dropped")
    t:eq(n[4].colour, "#008000", "a notehead's own colour when the note has none")
  end,
  entities_decode_in_part_names = function(t)
    local parsed = only({ { name = "Bells &amp; Chimes &lt;1&gt; &#233;&#x2019;", body = measure(DIVISIONS) } })
    t:eq(parsed.parts[1].name, "Bells & Chimes <1> \195\169\226\128\153")
  end,
  malformed_character_references_stay_as_written = function(t)
    -- past U+10FFFF, an "x" with no "#", a decimal with an exponent: none is a character, and none stops the read
    local parsed = only({ { name = "&#x400000; &#4194304; &x41; &#1e2;", body = measure(DIVISIONS) } })
    t:eq(parsed.parts[1].name, "&#x400000; &#4194304; &x41; &#1e2;")
  end,
  a_declared_entity_is_never_expanded = function(t)
    local text = '<!DOCTYPE score-partwise [ <!ENTITY e "x"> ]>'
      .. '<score-partwise><part-list><score-part id="P1"><part-name>&e;</part-name></score-part></part-list>'
      .. '<part id="P1"><measure/></part></score-partwise>'
    t:eq(musicxml.parse(text).parts[1].name, "&e;")
  end,
  attributes_and_cdata_decode = function(t)
    local text = '<score-partwise><part-list><score-part id="P&amp;1"><part-name><![CDATA[Bells & <Chimes>]]>'
      .. '</part-name></score-part></part-list><part id="P&amp;1"><measure/></part></score-partwise>'
    local part = musicxml.parse(text).parts[1]
    t:eq(part.id, "P&1")
    t:eq(part.name, "Bells & <Chimes>")
  end,
  doctype_and_comments_are_ignored = function(t)
    local text = '<?xml version="1.0"?>\n<!DOCTYPE score-partwise [ <!ENTITY e "x"> ]>\n<!-- a comment > here -->'
      .. '<score-partwise><part-list><score-part id="P1"><part-name>A</part-name></score-part></part-list>'
      .. '<part id="P1"><measure><!-- inside --><note><pitch><step>C</step><octave>4</octave></pitch>'
      .. "<duration>1</duration></note></measure></part></score-partwise>"
    local parsed = musicxml.parse(text)
    t:ok(parsed, "parsed")
    t:eq(#parsed.parts[1].notes, 1)
    t:eq(musicxml.parse("\239\187\191" .. text).parts[1].name, "A", "a byte-order mark first")
  end,
  refuses_what_it_cannot_read = function(t)
    local function code(text) return select(2, musicxml.parse(text)) end
    t:eq(code("PK\3\4rest of a zip"), "compressed")
    t:eq(code("<html><body/></html>"), "notMusicXML")
    t:eq(code(HEAD .. "<score-partwise/>"), "empty", "what Dorico writes for a flow made in the same run")
    t:eq(code("<score-partwise><part id='P1'><measure></part></score-partwise>"), "notMusicXML", "unclosed")
    t:eq(code("not xml at all"), "notMusicXML")
    t:eq(code(""), "notMusicXML")
  end,
  reads_the_fixture_export = function(t)
    local f = assert(io.open(here .. "data/fixture-full-score.musicxml", "rb"))
    local parsed = musicxml.parse(f:read("*a"))
    f:close()
    local names, diamonds = {}, 0
    for _, p in ipairs(parsed.parts) do
      names[#names + 1] = p.name
      for _, n in ipairs(p.notes) do
        if n.head == "diamond" then diamonds = diamonds + 1 end
      end
    end
    t:eq(table.concat(names, "|"), "Handbells (A)|Handbells (B)|Organ")
    t:eq(diamonds, 6)
    local first = parsed.parts[1].notes[1]
    t:eq(first.pitch, 72, "the fixture's first note, written C4, sounds C5")
    t:eq(first.pos, 0)
  end,
}
