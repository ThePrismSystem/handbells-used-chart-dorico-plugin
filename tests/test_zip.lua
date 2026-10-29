-- Entries of a zip archive, as a .dorico project is: the fixture project in fixtures/.
local zip = require("hbuc.zip")

local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"

local function fixture()
  local f = assert(io.open(here .. "../fixtures/handbells-fixture.dorico", "rb"))
  local bytes = f:read("*a")
  f:close()
  return bytes
end

local function errorOf(fn)
  local ok, err = pcall(fn)
  return not ok and tostring(err) or nil
end

-- The offset of the central directory record for name (1-based).
local function centralRecord(bytes, name)
  local at = 1
  while true do
    at = bytes:find("PK\1\2", at, true)
    if not at then return nil end
    local n = bytes:byte(at + 28) + bytes:byte(at + 29) * 256
    if bytes:sub(at + 46, at + 45 + n) == name then return at end
    at = at + 4
  end
end

return {
  reads_score_dtn = function(t)
    local dtn = zip.entry(fixture(), "score.dtn")
    t:eq(dtn:sub(1, 8), "\4\0\0\0\1\0\0\0", "a score.dtn header")
    t:ok(#dtn > 1000000, "the whole of it: " .. #dtn .. " bytes")
  end,
  reads_another_entry = function(t)
    t:ok(zip.entry(fixture(), "META-INF/container.xml"):find("<container", 1, true), "container.xml")
  end,
  missing_entry_is_nil = function(t)
    t:eq(zip.entry(fixture(), "nope.txt"), nil)
  end,
  not_a_zip = function(t)
    local err = errorOf(function() return zip.entry("hello", "x") end)
    t:ok(err and err:find("zip: ", 1, true), tostring(err))
  end,
  crc_mismatch = function(t)
    local bytes = fixture()
    local at = centralRecord(bytes, "score.dtn") + 16
    local flipped = bytes:sub(1, at - 1) .. string.char((bytes:byte(at) + 1) % 256) .. bytes:sub(at + 1)
    local err = errorOf(function() return zip.entry(flipped, "score.dtn") end)
    t:ok(err and err:find("zip: CRC", 1, true), tostring(err))
  end,
}
