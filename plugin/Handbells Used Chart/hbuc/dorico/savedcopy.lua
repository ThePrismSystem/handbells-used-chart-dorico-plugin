-- What Lua can't read from the open project, read from a copy of it saved into the temp folder: every note's notehead
-- set and colour (Lua can't read a value set by command or in Dorico's UI; hbuc.noteprops says why), the
-- instruments written at pitch, each layout's page, and every player's id. app:save(score, path) writes the current
-- state, unsaved edits included, without touching the project's own file, its path or its unsaved mark
-- (docs/dorico-lua-guide.md, section 3).
local chartlayout = require("hbuc.chartlayout")
local dtn = require("hbuc.dtn")
local noteprops = require("hbuc.noteprops")
local playerids = require("hbuc.playerids")
local transpose = require("hbuc.transpose")
local zip = require("hbuc.zip")
local files = require("hbuc.dorico.files")

local savedcopy = {}

local function readCopy(app, log, path, fromTree)
  local t0 = os.clock()
  local saved = app:save(app.currentScore, path)
  if saved ~= true then error("Dorico could not save a copy of the project to read", 0) end
  local bytes = files.read(path)
  local score = bytes and zip.entry(bytes, "score.dtn")
  if not score then error("the saved copy of the project could not be read", 0) end
  local t1 = os.clock()
  local out = fromTree(dtn.decode(score))
  log:line("saved copy:", #bytes, "bytes,", #score, "in score.dtn, saved in", string.format("%.2f", t1 - t0),
    "s, read in", string.format("%.2f", os.clock() - t1), "s")
  return out
end

-- The copy is the whole project, so one left behind goes in the log. The next run removes it first.
local function remove(log, path)
  local removed, why = files.remove(path)
  if not removed then log:line("the saved copy could not be deleted: " .. tostring(why)) end
end

local function fromCopy(app, log, tempDir, fromTree)
  local path = tempDir .. "reading.dorico"
  remove(log, path)
  local ok, out = pcall(readCopy, app, log, path, fromTree)
  remove(log, path)
  if not ok then error(out, 0) end
  return out
end

-- {notes = {[eventId] = entries} (hbuc.noteprops.fromTree) for every note and grace note in the project,
-- writtenAtPitch = {[instrument id] = true} (hbuc.transpose.writtenAtPitch),
-- pages = {[layout id] = page} (hbuc.chartlayout.pages)}.
function savedcopy.read(app, log, tempDir)
  return fromCopy(app, log, tempDir, function(tree)
    return { notes = noteprops.fromTree(tree), writtenAtPitch = transpose.writtenAtPitch(tree),
      pages = chartlayout.pages(tree) }
  end)
end

-- {[instrument id] = player id} (hbuc.playerids.fromTree) for every player in the project.
function savedcopy.playerIds(app, log, tempDir)
  return fromCopy(app, log, tempDir, playerids.fromTree)
end

return savedcopy
