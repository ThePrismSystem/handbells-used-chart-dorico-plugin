-- Every note's notehead set and colour, read from a copy of the project saved into the temp folder. Lua can't read
-- a value set by command or in Dorico's UI (hbuc.noteprops says why), but the saved score holds them all.
-- app:save(score, path) writes the current state, unsaved edits included, without touching the project's own file,
-- its path or its unsaved mark (docs/dorico-lua-guide.md, section 3).
local dtn = require("hbuc.dtn")
local noteprops = require("hbuc.noteprops")
local zip = require("hbuc.zip")
local files = require("hbuc.dorico.files")

local savedcopy = {}

local function readCopy(app, log, path)
  local t0 = os.clock()
  local saved = app:save(app.currentScore, path)
  if saved ~= true then error("Dorico could not save a copy of the project to read", 0) end
  local bytes = files.read(path)
  local score = bytes and zip.entry(bytes, "score.dtn")
  if not score then error("the saved copy of the project could not be read", 0) end
  local t1 = os.clock()
  local notes = noteprops.fromTree(dtn.decode(score))
  log:line("saved copy:", #bytes, "bytes,", #score, "in score.dtn, saved in", string.format("%.2f", t1 - t0),
    "s, read in", string.format("%.2f", os.clock() - t1), "s")
  return notes
end

-- The copy is the whole project, so one left behind goes in the log. The next run removes it first.
local function remove(log, path)
  local removed, why = files.remove(path)
  if not removed then log:line("the saved copy could not be deleted: " .. tostring(why)) end
end

-- {[eventId] = entries} (hbuc.noteprops.fromTree) for every note and grace note in the project.
function savedcopy.read(app, log, tempDir)
  local path = tempDir .. "reading.dorico"
  remove(log, path)
  local ok, notes = pcall(readCopy, app, log, path)
  remove(log, path)
  if not ok then error(notes, 0) end
  return notes
end

return savedcopy
