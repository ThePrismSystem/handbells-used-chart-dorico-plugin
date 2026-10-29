-- The shape rules of the Sibelius plugin's test/TestShapes.mss, with Dorico notehead set ids in place of
-- Sibelius note styles: built-in sets map by id (as BuiltInShape maps by index), custom sets by name.
local shapes = require("hbuc.shapes")
local constants = require("hbuc.constants")

local MATCH = constants.SHAPE_MATCH

return {
  built_in_sets = function(t)
    t:eq(shapes.ofNoteheadSet("noteheadset.default", "Default Noteheads"), "Round", "the plain head is round")
    t:eq(shapes.ofNoteheadSet("noteheadset.diamondNoteheads", "Raute"), "Diamond", "a built-in diamond whatever its name")
    t:eq(shapes.ofNoteheadSet("noteheadset.whiteDiamondNoteheads", ""), "Diamond")
    t:eq(shapes.ofNoteheadSet("noteheadset.Xnoteheads", "X Noteheads"), "", "the cross is none of the chart shapes")
    t:eq(shapes.ofNoteheadSet("noteheadset.xAndDiamond", "X and Diamond Noteheads"), "",
      "a built-in set is never read by its name")
    t:eq(shapes.ofNoteheadSet("noteheadset.triangleDownNoteheads", ""), "Inverted triangle")
    t:eq(shapes.ofNoteheadSet("noteheadset.largeArrowDownNoteheads", ""), "Inverted triangle", "the down arrow points down")
    t:eq(shapes.ofNoteheadSet("noteheadset.largeArrowUpNoteheads", ""), "Triangle", "the up arrow points up")
    t:eq(shapes.ofNoteheadSet("noteheadset.triangleUpNoteheads", ""), "Triangle")
    t:eq(shapes.ofNoteheadSet("noteheadset.rectangular", ""), "Square")
  end,
  sibelius_parity_for_slashes_and_fa = function(t)
    -- Sibelius maps Slashed/BackSlashed to Round and fa (ShapedNote4, a right triangle) to Triangle.
    t:eq(shapes.ofNoteheadSet("noteheadset.slashedNoteheadsBLTR", ""), "Round")
    t:eq(shapes.ofNoteheadSet("noteheadset.slashedNoteheadsTLBR", ""), "Round")
    t:eq(shapes.ofNoteheadSet("noteheadset.triangleleft", ""), "Triangle")
    t:eq(shapes.ofNoteheadSet("noteheadset.triangleright", ""), "Triangle")
  end,
  custom_sets_by_name = function(t)
    t:eq(shapes.ofNoteheadSet("custom.1", "Black & white diamond (2)"), "Diamond", "a copied diamond by name")
    t:eq(shapes.ofNoteheadSet("custom.2", "Inverted triangle (2)"), "Inverted triangle", "inverted before triangle")
    t:eq(shapes.ofNoteheadSet("custom.3", "Triangle (stemless)"), "Triangle", "a triangle by name")
    t:eq(shapes.ofNoteheadSet("custom.4", "SQUARE"), "Square", "case makes no difference")
    t:eq(shapes.ofNoteheadSet("custom.5", "Cross (2)"), "", "a cross is no shape by name either")
    t:eq(shapes.ofNoteheadSet("custom.6", "Half circle (stemless)"), "Half circle", "a half circle by name")
    t:eq(shapes.ofNoteheadSet("custom.7", "Cone (stemless)"), "Cone", "a cone by name")
    t:eq(shapes.ofNoteheadSet("custom.8", "Normal (2)"), "Round", "a copy of the plain head is round")
    t:eq(shapes.ofNoteheadSet("custom.9", "Chime"), "", "a name with no shape in it has no shape")
  end,
  chart_shape = function(t)
    t:eq(shapes.chartShape("Square", "noteheadset.diamondNoteheads", "Diamond Noteheads", "chimes"), "Square",
      "a chosen shape wins")
    t:eq(shapes.chartShape(MATCH, "noteheadset.diamondNoteheads", "Diamond Noteheads", "bells"), "Diamond",
      "matching follows the notehead")
    t:eq(shapes.chartShape("", "custom.7", "Cone (stemless)", "smbs"), "Cone", "an empty choice also matches")
    t:eq(shapes.chartShape(MATCH, "noteheadset.Xnoteheads", "X Noteheads", "smbs"), "Square", "no shape: SMBs are square")
    t:eq(shapes.chartShape(MATCH, "custom.9", "Chime", "chimes"), "Diamond", "no shape: chimes are diamonds")
    t:eq(shapes.chartShape(MATCH, "custom.9", "Chime", "smbs"), "Square")
    t:eq(shapes.chartShape(MATCH, "custom.9", "Chime", "bells"), "Round", "no shape: bells are round")
    t:eq(shapes.chartShape(MATCH, "custom.9", "Chime", "pf"), "Round")
    t:eq(shapes.chartShape(MATCH, "custom.9", "Chime", "whitechapel"), "Round")
  end,
  items_and_preferred = function(t)
    local items = shapes.items()
    t:eq(#items, 8, "matching and seven shapes")
    t:eq(items[1], MATCH, "matching comes first")
    t:eq(items[2], "Round", "then round")
    t:eq(items[8], "Cone", "and the cone last")
    t:eq(shapes.preferred("Square"), "Square", "a remembered shape is kept")
    t:eq(shapes.preferred("Hexagon"), MATCH, "an unknown shape opens on matching")
    t:eq(shapes.preferred(""), MATCH, "nothing remembered opens on matching")
  end,
  notehead_set_for_shape = function(t)
    t:eq(shapes.noteheadSetFor("Round"), "noteheadset.default")
    t:eq(shapes.noteheadSetFor("Diamond"), "noteheadset.diamondNoteheads")
    t:eq(shapes.noteheadSetFor("Square"), "noteheadset.rectangular")
    t:eq(shapes.noteheadSetFor("Triangle"), "noteheadset.triangleUpNoteheads")
    t:eq(shapes.noteheadSetFor("Inverted triangle"), "noteheadset.triangleDownNoteheads")
  end,
  half_circle_and_cone_have_no_set = function(t)
    t:eq(shapes.noteheadSetFor("Half circle"), nil)
    t:eq(shapes.noteheadSetFor("Cone"), nil)
  end,
  display_names = function(t)
    t:eq(shapes.displayName("noteheadset.rectangular"), "Rectangular Noteheads")
    t:eq(shapes.displayName("noteheadset.diamondNoteheads"), "Diamond Noteheads")
    t:eq(shapes.displayName("custom.x"), "custom.x")
  end,
  -- What Dorico 6.2.30 writes for each built-in set (spike/48_notehead_survey.py); a value several sets share names
  -- the plain one.
  musicxml_heads_map_to_dorico_sets = function(t)
    local want = {
      { "diamond", nil, "noteheadset.diamondNoteheads" },
      { "diamond", true, "noteheadset.diamondNoteheads" },
      { "diamond", false, "noteheadset.whiteDiamondNoteheads" },
      { "triangle", nil, "noteheadset.triangleUpNoteheads" },
      { "inverted triangle", nil, "noteheadset.triangleDownNoteheads" },
      { "x", nil, "noteheadset.Xnoteheads" },
      { "slash", nil, "noteheadset.slashNoteheads" },
      { "circle-x", nil, "noteheadset.circleXNoteheads" },
      { "circled", nil, "noteheadset.largeCircledNoteheads" },
      { "cross", nil, "noteheadset.withXNoteheads" },
      { "slashed", nil, "noteheadset.slashedNoteheadsBLTR" },
      { "back slashed", nil, "noteheadset.slashedNoteheadsTLBR" },
      { "arrow up", nil, "noteheadset.largeArrowUpNoteheads" },
      { "arrow down", nil, "noteheadset.largeArrowDownNoteheads" },
      { "do", nil, "noteheadset.aikin7Shape" },
    }
    for _, w in ipairs(want) do
      t:eq(shapes.fromMusicXML(w[1], w[2]), w[3], w[1] .. " filled " .. tostring(w[2]))
    end
  end,
  no_musicxml_head_is_not_in_musicxml = function(t)
    t:eq(shapes.NOT_IN_MUSICXML, "noteheadset.notInMusicXML")
    t:eq(shapes.fromMusicXML(nil), shapes.NOT_IN_MUSICXML, "no <notehead>")
    t:eq(shapes.fromMusicXML(""), shapes.NOT_IN_MUSICXML, "an empty one")
    t:eq(shapes.fromMusicXML("normal"), shapes.NOT_IN_MUSICXML, "the plain head, written out")
    t:eq(shapes.displayName(shapes.NOT_IN_MUSICXML), "Changed in Dorico (not in MusicXML)")
  end,
  not_in_musicxml_charts_as_the_kinds_default = function(t)
    local name = shapes.displayName(shapes.NOT_IN_MUSICXML)
    t:eq(shapes.chartShape(MATCH, shapes.NOT_IN_MUSICXML, name, "smbs"), "Square")
    t:eq(shapes.chartShape(MATCH, shapes.NOT_IN_MUSICXML, name, "chimes"), "Diamond")
  end,
  other_musicxml_heads_keep_their_name = function(t)
    t:eq(shapes.fromMusicXML("square"), "musicxml.square")
    t:eq(shapes.displayName("musicxml.square"), "square (MusicXML)")
    t:eq(shapes.chartShape(MATCH, "musicxml.square", shapes.displayName("musicxml.square"), "bells"), "Square",
      "its shape is read from its name, as a custom set's is")
  end,
}
