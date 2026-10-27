-- Bell names and chart regions, ported from the Sibelius plugin's BellName.mss and Pitch.mss.
-- Bell space: a bell's name is its sounding pitch, an octave above written. The diatonic index is
-- octave * 7 + letter step (C = 0 ... B = 6), so middle C (C4) is pitch 60, diatonic 28.
local bellname = {}

local LETTERS = { "C", "D", "E", "F", "G", "A", "B" }
local NATURAL_OFFSET = { 0, 2, 4, 5, 7, 9, 11 }
local STEP_OF = { C = 0, D = 1, E = 2, F = 3, G = 4, A = 5, B = 6 }
local ACCIDENTAL_TEXT = { [-2] = "bb", [-1] = "b", [0] = "", [1] = "#", [2] = "x" }
-- "##" too: a double sharp may be printed as two sharps.
local ALTER_OF = { [""] = 0, ["#"] = 1, ["x"] = 2, ["##"] = 2, ["b"] = -1, ["bb"] = -2 }

-- The octave comes from the diatonic index, never from the pitch: Cb5 is octave 5 though it sounds as B4.
function bellname.nameOf(pitch, diatonic)
  local step = diatonic % 7
  local octave = math.floor(diatonic / 7)
  local letter = LETTERS[step + 1]
  local natural = (octave + 1) * 12 + NATURAL_OFFSET[step + 1]
  local alter = pitch - natural
  return {
    pitch = pitch,
    diatonic = diatonic,
    letter = letter,
    alter = alter,
    octave = octave,
    -- As AccidentalText: nothing beyond a double sharp or flat has text of its own.
    name = letter .. (ACCIDENTAL_TEXT[alter] or "") .. octave,
  }
end

-- The six regions are contiguous diatonic ranges covering C2 (14) through C9 (63).
function bellname.regionOf(diatonic)
  if diatonic >= 14 and diatonic <= 20 then return "bassRow2" end
  if diatonic >= 21 and diatonic <= 27 then return "bassRow1" end
  if diatonic >= 28 and diatonic <= 35 then return "bassStaff" end
  if diatonic >= 36 and diatonic <= 49 then return "trebleStaff" end
  if diatonic >= 50 and diatonic <= 56 then return "trebleRow1" end
  if diatonic >= 57 and diatonic <= 63 then return "trebleRow2" end
  return ""
end

-- A spelling as Dorico prints it ("G#5", "Ab4", "Fx4", "Ebb4", "B-1") to {pitch, diatonic}, or nil.
function bellname.fromSpelling(s)
  local letter, accidental, octave = tostring(s):match("^([A-G])([#bx]*)(%-?%d+)$")
  if not letter then return nil end
  local alter = ALTER_OF[accidental]
  if alter == nil then return nil end
  octave = tonumber(octave)
  local step = STEP_OF[letter]
  return {
    pitch = (octave + 1) * 12 + NATURAL_OFFSET[step + 1] + alter,
    diatonic = octave * 7 + step,
  }
end

-- The spelling Dorico's MIDIPitchWithSpelling.fromString accepts for a pitch and diatonic index.
-- nil beyond a double sharp or flat: there is no spelling for it, and a malformed one must never reach Dorico.
function bellname.toSpelling(pitch, diatonic)
  local n = bellname.nameOf(pitch, diatonic)
  if not ACCIDENTAL_TEXT[n.alter] then return nil end
  return n.name
end

-- Written pitch to bell space and back: handbells sound an octave above written.
function bellname.fromWritten(pitch, diatonic)
  return { pitch = pitch + 12, diatonic = diatonic + 7 }
end

function bellname.toWritten(pitch, diatonic)
  return { pitch = pitch - 12, diatonic = diatonic - 7 }
end

return bellname
