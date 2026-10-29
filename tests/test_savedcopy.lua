-- Reading noteheads and colours from a copy of the project that the run saves into its temp folder, against a fake
-- app whose save writes the fixture project's bytes.
local files = require("hbuc.dorico.files")
local savedcopy = require("hbuc.dorico.savedcopy")

local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
local temp = ((os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("\\", "/")):gsub("/?$", "/")
local log = { line = function() end }

-- A temp folder of the test's own. Stock Lua has no lfs to make one with, but savedcopy only adds the file's name to
-- it, so a prefix of its own in the temp folder does.
local made = 0
local function tempDir()
  made = made + 1
  return temp .. "hbuc-test-" .. os.time() .. "-" .. made .. "-"
end

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
    local dir, seen = tempDir(), {}
    local notes = savedcopy.read(app(fixture(), true, seen), log, dir)
    t:eq(seen.path, dir .. "reading.dorico", "saved into the temp folder")
    t:ok(notes[209], "a fixture note")
    t:ok(not exists(seen.path), "the copy is gone")
  end,
  a_leftover_copy_is_removed_first = function(t)
    local dir, seen = tempDir(), {}
    files.write(dir .. "reading.dorico", "left over")
    savedcopy.read(app(fixture(), true, seen), log, dir)
    t:ok(not seen.existed, "no file there when Dorico saves")
  end,
  a_refused_save = function(t)
    local err = errorOf(function() return savedcopy.read(app(nil, false), log, tempDir()) end)
    t:ok(err and err:find("could not save a copy", 1, true), tostring(err))
  end,
  a_save_that_writes_nothing = function(t)
    local err = errorOf(function() return savedcopy.read(app(nil, true), log, tempDir()) end)
    t:ok(err and err:find("could not be read", 1, true), tostring(err))
  end,
  a_copy_that_is_not_a_project = function(t)
    local dir = tempDir()
    local err = errorOf(function() return savedcopy.read(app("not a zip", true), log, dir) end)
    t:ok(err, "fails")
    t:ok(not exists(dir .. "reading.dorico"), "and the copy is still deleted")
  end,
}
