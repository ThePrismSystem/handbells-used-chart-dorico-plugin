-- The binary tree Dorico saves a project's score in (score.dtn): spike/lib/dtn.py describes the layout.
local dtn = require("hbuc.dtn")
local zip = require("hbuc.zip")

local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
local floor = math.floor

local function u32(n)
  return string.char(n % 256, floor(n / 256) % 256, floor(n / 65536) % 256, floor(n / 16777216) % 256)
end

local function varint(n)
  local out = {}
  repeat
    local b = n % 128
    n = floor(n / 128)
    out[#out + 1] = string.char(n > 0 and b + 128 or b)
  until n == 0
  return table.concat(out)
end

-- records: {tag, name index, value index, child ids (for a tag with bit 2 set)}
local function encode(names, values, records)
  local out = { u32(4), u32(1), u32(#names) }
  for _, s in ipairs(names) do out[#out + 1] = s .. "\0" end
  out[#out + 1] = u32(#values)
  for _, s in ipairs(values) do out[#out + 1] = s .. "\0" end
  out[#out + 1] = u32(#records)
  for _, r in ipairs(records) do
    out[#out + 1] = string.char(r[1]) .. varint(r[2]) .. varint(r[3])
    if r[1] % 4 >= 2 then
      out[#out + 1] = varint(#r[4])
      for _, k in ipairs(r[4]) do out[#out + 1] = varint(k) end
    end
  end
  return table.concat(out)
end

-- root "a" holding leaf "b" = "x"; the root's tag has the high nibble 0x1, the leaf's 0x2, as two saves wrote them
local TINY = encode({ "a", "b" }, { "", "x" }, { { 0x12, 0, 0, { 1 } }, { 0x20, 1, 1 } })

local function errorOf(fn)
  local ok, err = pcall(fn)
  return not ok and tostring(err) or nil
end

local function fails(t, bytes, label)
  local err = errorOf(function() return dtn.decode(bytes) end)
  t:ok(err and err:find("dtn: ", 1, true), label .. ": " .. tostring(err))
end

return {
  tiny_tree = function(t)
    local tree = dtn.decode(TINY)
    t:eq(dtn.name(tree, 0), "a")
    local b = dtn.child(tree, 0, "b")
    t:eq(b, 1, "the leaf")
    t:eq(dtn.value(tree, b), "x")
    t:eq(#dtn.children(tree, 0), 1, "one child")
    t:eq(#dtn.children(tree, 1), 0, "a leaf has none")
    t:eq(dtn.child(tree, 0, "c"), nil, "no such child")
  end,
  trailing_bytes = function(t) fails(t, TINY .. "\0", "trailing") end,
  truncated = function(t) fails(t, TINY:sub(1, -2), "truncated") end,
  bad_header = function(t) fails(t, "\5" .. TINY:sub(2), "header") end,
  child_out_of_range = function(t)
    fails(t, encode({ "a" }, { "" }, { { 0x22, 0, 0, { 7 } } }), "child 7 of 1 node")
  end,
  fixture = function(t)
    local f = assert(io.open(here .. "../fixtures/handbells-fixture.dorico", "rb"))
    local bytes = f:read("*a")
    f:close()
    t:eq(dtn.name(dtn.decode(zip.entry(bytes, "score.dtn")), 0), "kScore")
  end,
}
