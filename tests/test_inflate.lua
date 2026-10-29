-- Raw DEFLATE (RFC 1951), as a .dorico zip stores score.dtn. The compressed vectors come from Python's
-- zlib.compressobj(9, zlib.DEFLATED, -15).
local inflate = require("hbuc.inflate")

local function hex(s)
  return (s:gsub("%s", ""):gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end))
end

-- b"abcabcabcabcabcabc hello hello hello": one block of fixed Huffman codes
local FIXED = hex("4b4c4a4e44450a19a93939f9c82400")

-- 300 bytes ((i * 7) % 251), 32,000 "a"s, the same 300 bytes again: a dynamic block, matches of length 258, and a
-- distance of 32,300
local FAR = hex([[
edddd72216000040e1df4824b4140d231545a43dadd2929d5219914283b6cade8aa234ec325348464b6646458b8ca6d2de4693ab6e3c00
f7e77b83f3044730505a76acca14edb9ba4b8d576f7074dde9e1131c111d979c997bb5a4aaaee1e9eb8f3f7e0b89cb8c1c37417dfa3cbd
652656369bb6ee3ae01b72f4647cca85cbd74aabef3d7ed6f6a9fd8fb0c490510a133566ccd75f6ebac6d669dbee837ea1c74e25a45ecc
bb5e5673bff1f99bcf1d7f45060d95539c3475e6028315666bed366fdf73c83f2cf274625a56fe8df2db0f9a5ebcfdd2f94f547298bc92
aae6ac858b579a5bdb6fd9b1d733e070d499a4f4ec82a28a3b0f9b5fbefbdad53d60f0f0d1ca6a5ab3172d31b258b7d1d96d9f57e091e3
316733720a6fdebafba8a5f5fdb79f3d625223c68c9f3c6d8e8ee12acbf50e2eeefbbd83c24fc49e3b7fe94a71656dfd93571fbeff12f4
37dd01000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007a0978c5f739
fd3f]])

local function farInput()
  local chunk = {}
  for i = 0, 299 do chunk[#chunk + 1] = string.char((i * 7) % 251) end
  chunk = table.concat(chunk)
  return chunk .. string.rep("a", 32000) .. chunk
end

local function errorOf(fn)
  local ok, err = pcall(fn)
  return not ok and tostring(err) or nil
end

return {
  stored_block = function(t)
    t:eq(inflate.raw(hex("0105 00fa ff68 656c 6c6f")), "hello")
  end,
  start_offset = function(t)
    t:eq(inflate.raw("xy" .. hex("0105 00fa ff68 656c 6c6f"), 3), "hello", "decoding starts at byte 3")
  end,
  fixed_huffman = function(t)
    t:eq(inflate.raw(FIXED), "abcabcabcabcabcabc hello hello hello")
  end,
  dynamic_huffman_long_match_and_distance = function(t)
    local got = inflate.raw(FAR)
    t:eq(#got, 32600, "length")
    t:ok(got == farInput(), "the bytes come back exactly")
  end,
  -- b"ab" * 2000, a sync flush (an empty stored block), then b"world". The dynamic block's end-of-block code is short
  -- enough that the decoder has already read a byte of the stored block's header when it gets there.
  stored_block_after_read_ahead = function(t)
    local got = inflate.raw(hex("ecc2310d00000002a0acda3f84317c18a401000000ce060000ffff2bcf2fca490100"))
    t:ok(got == string.rep("ab", 2000) .. "world", "got " .. #got .. " bytes")
  end,
  invalid_block_type = function(t)
    local err = errorOf(function() return inflate.raw(hex("07")) end)
    t:ok(err and err:find("inflate: invalid block type", 1, true), tostring(err))
  end,
  truncated_input = function(t)
    local err = errorOf(function() return inflate.raw(FIXED:sub(1, -3)) end)
    t:ok(err and err:find("inflate: ", 1, true), tostring(err))
  end,
}
