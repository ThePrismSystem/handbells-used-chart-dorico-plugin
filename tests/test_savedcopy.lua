-- Reading noteheads and colours from a copy of the project that the run saves into its temp folder, against a fake
-- app whose save writes the fixture project's bytes.
local files = require("hbuc.dorico.files")
local savedcopy = require("hbuc.dorico.savedcopy")

local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
-- the temp folder itself: stock Lua has no lfs to make one inside it with
local temp = ((os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("\\", "/")):gsub("/?$", "/")
local COPY = temp .. "reading.dorico"
local log = { line = function() end }

local function fixture()
  local f = assert(io.open(here .. "../fixtures/handbells-fixture.dorico", "rb"))
  local bytes = f:read("*a")
  f:close()
  return bytes
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() end
  return f ~= nil
end

-- An app whose save(score, path) writes bytes there (nothing when bytes is nil) and returns result.
local function app(bytes, result, seen)
  return {
    currentScore = {},
    save = function(_, _, path)
      if seen then seen.path, seen.existed = path, exists(path) end
      if bytes then files.write(path, bytes) end
      return result
    end,
  }
end

local function errorOf(fn)
  local ok, err = pcall(fn)
  return not ok and tostring(err) or nil
end

return {
  reads_the_copy_and_deletes_it = function(t)
    local seen = {}
    local notes = savedcopy.read(app(fixture(), true, seen), log, temp)
    t:eq(seen.path, COPY, "saved into the temp folder")
    t:ok(notes[209], "a fixture note")
    t:ok(not exists(COPY), "the copy is gone")
  end,
  a_leftover_copy_is_removed_first = function(t)
    files.write(COPY, "left over")
    local seen = {}
    savedcopy.read(app(fixture(), true, seen), log, temp)
    t:ok(not seen.existed, "no file there when Dorico saves")
  end,
  a_refused_save = function(t)
    local err = errorOf(function() return savedcopy.read(app(nil, false), log, temp) end)
    t:ok(err and err:find("could not save a copy", 1, true), tostring(err))
  end,
  a_save_that_writes_nothing = function(t)
    local err = errorOf(function() return savedcopy.read(app(nil, true), log, temp) end)
    t:ok(err and err:find("could not be read", 1, true), tostring(err))
  end,
  a_copy_that_is_not_a_project = function(t)
    local err = errorOf(function() return savedcopy.read(app("not a zip", true), log, temp) end)
    t:ok(err, "fails")
    t:ok(not exists(COPY), "and the copy is still deleted")
  end,
}
