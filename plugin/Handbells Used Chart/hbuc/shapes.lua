-- Chart shapes for Dorico notehead sets, ported from the Sibelius plugin's Shapes.mss. Dorico's built-in
-- sets have fixed ids and are mapped by id (as Sibelius's built-in styles are mapped by index); any other set
-- is read by its display name.
local constants = require("hbuc.constants")

local shapes = {}

-- The 37 built-in notehead sets of Dorico 6 and their display names.
local DISPLAY = {
  ["noteheadset.aikin7Shape"] = "Aikin 7-shape Noteheads",
  ["noteheadset.circleXNoteheads"] = "Circle X Noteheads",
  ["noteheadset.circledNoteheads"] = "Circled Noteheads",
  ["noteheadset.default"] = "Default Noteheads",
  ["noteheadset.diamondNoteheads"] = "Diamond Noteheads",
  ["noteheadset.figurenotes"] = "Figurenotes Noteheads",
  ["noteheadset.funk7Shape"] = "Funk 7-shape Noteheads",
  ["noteheadset.largeArrowDownNoteheads"] = "Large Arrow Down Noteheads",
  ["noteheadset.largeArrowUpNoteheads"] = "Large Arrow Up Noteheads",
  ["noteheadset.largeCircledNoteheads"] = "Large Circled Noteheads",
  ["noteheadset.largeXAndDiamond"] = "Large X and Diamond Noteheads",
  ["noteheadset.large"] = "Larger Noteheads",
  ["noteheadset.moon"] = "Moon Noteheads",
  ["noteheadset.mutedSlashNoteheads"] = "Muted Slash Noteheads",
  ["noteheadset.oldDiamondNoteheads"] = "Old-Style Diamond Noteheads",
  ["noteheadset.ornatex"] = "Ornate X Noteheads",
  ["noteheadset.slashNoteheadsOversized"] = "Oversized Slash Noteheads",
  ["noteheadset.noteNames"] = "Pitch Name Noteheads",
  ["noteheadset.plusNoteheads"] = "Plus Noteheads",
  ["noteheadset.rectangular"] = "Rectangular Noteheads",
  ["noteheadset.roundWhiteWithDot"] = "Round White with Dot Noteheads",
  ["noteheadset.slashNoteheads"] = "Slash Noteheads",
  ["noteheadset.slashedNoteheadsBLTR"] = "Slashed Noteheads (Bottom Left to Top Right)",
  ["noteheadset.slashedNoteheadsTLBR"] = "Slashed Noteheads (Top Left to Bottom Right)",
  ["noteheadset.slashNoteheadsSmall"] = "Small Slash Noteheads",
  ["noteheadset.triangleDownNoteheads"] = "Triangle Down Noteheads",
  ["noteheadset.triangleleft"] = "Triangle Left Noteheads",
  ["noteheadset.triangleright"] = "Triangle Right Noteheads",
  ["noteheadset.triangleUpNoteheads"] = "Triangle Up Noteheads",
  ["noteheadset.walker4Shape"] = "Walker 4-shape Noteheads",
  ["noteheadset.walker7Shape"] = "Walker 7-shape Noteheads",
  ["noteheadset.whiteDiamondNoteheads"] = "White Diamond Noteheads",
  ["noteheadset.wideDiamondNoteheads"] = "Wide Diamond Noteheads",
  ["noteheadset.withXNoteheads"] = "With X Noteheads",
  ["noteheadset.Xnoteheads"] = "X Noteheads",
  ["noteheadset.xAndCircleX"] = "X and Circle X Noteheads",
  ["noteheadset.xAndDiamond"] = "X and Diamond Noteheads",
}

local BUILT_IN_SHAPE = {
  ["noteheadset.default"] = "Round",
  ["noteheadset.large"] = "Round",
  ["noteheadset.circledNoteheads"] = "Round",
  ["noteheadset.largeCircledNoteheads"] = "Round",
  ["noteheadset.roundWhiteWithDot"] = "Round",
  -- Sibelius reads its slashed and back-slashed heads as round, and fa (a right triangle) as a triangle.
  ["noteheadset.slashedNoteheadsBLTR"] = "Round",
  ["noteheadset.slashedNoteheadsTLBR"] = "Round",
  ["noteheadset.triangleleft"] = "Triangle",
  ["noteheadset.triangleright"] = "Triangle",
  ["noteheadset.diamondNoteheads"] = "Diamond",
  ["noteheadset.whiteDiamondNoteheads"] = "Diamond",
  ["noteheadset.oldDiamondNoteheads"] = "Diamond",
  ["noteheadset.wideDiamondNoteheads"] = "Diamond",
  ["noteheadset.rectangular"] = "Square",
  ["noteheadset.triangleUpNoteheads"] = "Triangle",
  ["noteheadset.largeArrowUpNoteheads"] = "Triangle",
  ["noteheadset.triangleDownNoteheads"] = "Inverted triangle",
  ["noteheadset.largeArrowDownNoteheads"] = "Inverted triangle",
}

-- The set a chart draws each shape with. Half circle and cone have no built-in Dorico set.
local SET_FOR_SHAPE = {
  Round = "noteheadset.default",
  Diamond = "noteheadset.diamondNoteheads",
  Square = "noteheadset.rectangular",
  Triangle = "noteheadset.triangleUpNoteheads",
  ["Inverted triangle"] = "noteheadset.triangleDownNoteheads",
}

function shapes.items()
  local items = { constants.SHAPE_MATCH }
  for _, s in ipairs(constants.SHAPES) do items[#items + 1] = s end
  return items
end

function shapes.preferred(remembered)
  for _, s in ipairs(constants.SHAPES) do
    if s == remembered then return remembered end
  end
  return constants.SHAPE_MATCH
end

-- Keyword order matters: "inverted triangle" must not read as a triangle.
local function namedShape(name)
  local text = tostring(name or ""):lower()
  local function has(word) return text:find(word, 1, true) ~= nil end
  if has("inverted") then return "Inverted triangle" end
  if has("triangle") then return "Triangle" end
  if has("diamond") then return "Diamond" end
  if has("square") then return "Square" end
  if has("half circle") then return "Half circle" end
  if has("cone") then return "Cone" end
  if has("normal") or has("round") or has("stemless") then return "Round" end
  return ""
end

-- The chart shape a notehead set looks like, or "" when it is none of them.
function shapes.ofNoteheadSet(id, displayName)
  if DISPLAY[id] then return BUILT_IN_SHAPE[id] or "" end
  return namedShape(displayName)
end

function shapes.defaultShape(kind)
  if kind == "chimes" then return "Diamond" end
  if kind == "smbs" then return "Square" end
  return "Round"
end

-- The shape a section is drawn in: the user's choice, else the shape of the music's notehead, else the default.
function shapes.chartShape(choice, id, displayName, kind)
  if choice ~= nil and choice ~= "" and choice ~= constants.SHAPE_MATCH then return choice end
  local shape = shapes.ofNoteheadSet(id, displayName)
  if shape ~= "" then return shape end
  return shapes.defaultShape(kind)
end

function shapes.noteheadSetFor(shape)
  return SET_FOR_SHAPE[shape]
end

-- Lua can't read a notehead changed in Dorico's UI, so it comes from a MusicXML export instead. Some sets export no
-- <notehead> at all (Rectangular, Wide Diamond and more: spike/48_notehead_survey.py). All we know of such a note
-- is that its head was changed, which still keeps it apart from plain heads.
shapes.NOT_IN_MUSICXML = "noteheadset.notInMusicXML"

-- What Dorico 6 writes for its built-in sets. A value several sets share (x, slash) names the plain one.
local FROM_MUSICXML = {
  diamond = "noteheadset.diamondNoteheads",
  triangle = "noteheadset.triangleUpNoteheads",
  ["inverted triangle"] = "noteheadset.triangleDownNoteheads",
  x = "noteheadset.Xnoteheads",
  slash = "noteheadset.slashNoteheads",
  ["circle-x"] = "noteheadset.circleXNoteheads",
  circled = "noteheadset.largeCircledNoteheads",
  cross = "noteheadset.withXNoteheads",
  slashed = "noteheadset.slashedNoteheadsBLTR",
  ["back slashed"] = "noteheadset.slashedNoteheadsTLBR",
  ["arrow up"] = "noteheadset.largeArrowUpNoteheads",
  ["arrow down"] = "noteheadset.largeArrowDownNoteheads",
  ["do"] = "noteheadset.aikin7Shape",
}

-- The head id of a note's MusicXML <notehead> (text, and its filled attribute), for a note whose head Lua couldn't
-- read. Any other value keeps its own id, named after the value.
function shapes.fromMusicXML(text, filled)
  if text == nil or text == "" or text == "normal" then return shapes.NOT_IN_MUSICXML end
  if text == "diamond" and filled == false then return "noteheadset.whiteDiamondNoteheads" end
  return FROM_MUSICXML[text] or ("musicxml." .. text)
end

function shapes.displayName(id)
  if id == shapes.NOT_IN_MUSICXML then return constants.NOT_IN_MUSICXML_NAME end
  local value = tostring(id):match("^musicxml%.(.+)$")
  if value then return string.format(constants.MUSICXML_HEAD_NAME, value) end
  return DISPLAY[id] or id
end

return shapes
