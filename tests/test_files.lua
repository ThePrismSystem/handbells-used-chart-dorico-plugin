-- Removing the plug-in's own files: a file that isn't there is no failure, and one that stays says why.
local files = require("hbuc.dorico.files")

local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
local temp = ((os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("\\", "/")):gsub("/?$", "/")

local made = 0
local function unique(name)
  made = made + 1
  return temp .. "hbuc-test-" .. os.time() .. "-" .. made .. "-" .. name
end

-- Runs fn with lfs as fake, or with no lfs to load when fake is nil.
local function withLfs(fake, fn)
  local loaded, preload = package.loaded.lfs, package.preload.lfs
  package.loaded.lfs = fake
  if not fake then package.preload.lfs = function() error("no lfs here") end end
  local ok, err = pcall(fn)
  package.loaded.lfs, package.preload.lfs = loaded, preload
  if not ok then error(err, 0) end
end

return {
  -- Without lfs, which a Mac may lack, a save is told by the file's bytes: each save stamps its time into the zip.
  without_lfs_the_stamp_is_the_file_s_bytes = function(t)
    withLfs(nil, function()
      local path = unique("stamp.txt")
      files.write(path, "first")
      t:eq(files.stamp(path), "first")
      files.write(path, "second")
      t:eq(files.stamp(path), "second")
      files.remove(path)
      t:eq(files.stamp(path), nil, "a file that can't be read")
    end)
  end,
  with_lfs_the_stamp_is_the_modification_time = function(t)
    withLfs({ attributes = function(path, what) return path == "p" and what == "modification" and 42 or nil end },
      function() t:eq(files.stamp("p"), 42) end)
  end,
  remove_deletes_a_file = function(t)
    local path = unique("remove.txt")
    files.write(path, "x")
    t:eq(files.remove(path), true)
    t:eq(io.open(path, "rb"), nil, "gone")
  end,
  a_missing_file_is_no_failure = function(t)
    t:eq(files.remove(unique("never-made.txt")), true)
  end,
  -- the tests folder, which os.remove can't take away while it holds files
  a_file_that_stays_says_why = function(t)
    local ok, why = files.remove(here:sub(1, -2))
    t:eq(ok, false)
    t:ok(type(why) == "string" and why ~= "", tostring(why))
  end,
}
