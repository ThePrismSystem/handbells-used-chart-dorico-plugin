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

local function fails(t, bytes, reason)
  local err = errorOf(function() return zip.entry(bytes, "a.txt") end)
  t:ok(err and err:find("zip: " .. reason, 1, true), reason .. ": " .. tostring(err))
end

local function u16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
local function u32(n) return u16(n % 65536) .. u16(math.floor(n / 65536)) end

local HELLO_CRC = 0x3610a686

-- An archive of one entry, "a.txt" holding "hello" stored as it is. o changes a field: {method, size, localOffset,
-- count, centralOffset, comment}.
local function archive(o)
  o = o or {}
  local name, data, method = "a.txt", "hello", o.method or 0
  local sizes = u32(HELLO_CRC) .. u32(#data) .. u32(o.size or #data)
  local header = "PK\3\4" .. u16(20) .. u16(0) .. u16(method) .. u16(0) .. u16(0) .. sizes .. u16(#name) .. u16(0)
    .. name
  local central = "PK\1\2" .. u16(20) .. u16(20) .. u16(0) .. u16(method) .. u16(0) .. u16(0) .. sizes
    .. u16(#name) .. u16(0) .. u16(0) .. u16(0) .. u16(0) .. u32(0) .. u32(o.localOffset or 0) .. name
  local comment, count = o.comment or "", o.count or 1
  return header .. data .. central .. "PK\5\6" .. u16(0) .. u16(0) .. u16(count) .. u16(count) .. u32(#central)
    .. u32(o.centralOffset or #header + #data) .. u16(#comment) .. comment
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
  a_stored_entry = function(t)
    t:eq(zip.entry(archive(), "a.txt"), "hello")
  end,
  a_comment_after_the_end_record = function(t)
    t:eq(zip.entry(archive({ comment = "made by hand" }), "a.txt"), "hello")
  end,
  an_unsupported_method = function(t) fails(t, archive({ method = 12 }), "unsupported compression method 12") end,
  a_size_mismatch = function(t) fails(t, archive({ size = 100000 }), "size mismatch for a.txt") end,
  zip64 = function(t) fails(t, archive({ count = 0xFFFF }), "ZIP64 archives are not supported") end,
  a_bad_central_directory = function(t) fails(t, archive({ centralOffset = 0 }), "bad central directory") end,
  a_bad_local_header = function(t) fails(t, archive({ localOffset = 1 }), "bad local header for a.txt") end,
}
