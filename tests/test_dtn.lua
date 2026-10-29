-- The binary tree Dorico saves a project's score in (score.dtn): spike/lib/dtn.py describes the layout.
local dtn = require("hbuc.dtn")
local zip = require("hbuc.zip")

local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
local encode = require("dtn_build").encode

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
