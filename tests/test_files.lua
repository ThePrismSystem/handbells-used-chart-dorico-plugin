-- Removing the plug-in's own files: a file that isn't there is no failure, and one that stays says why.
local files = require("hbuc.dorico.files")

local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
local temp = ((os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("\\", "/")):gsub("/?$", "/")

local made = 0
local function unique(name)
  made = made + 1
  return temp .. "hbuc-test-" .. os.time() .. "-" .. made .. "-" .. name
end

return {
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
