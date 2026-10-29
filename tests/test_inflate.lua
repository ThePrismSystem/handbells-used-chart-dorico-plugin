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

local function fails(t, data, reason)
  local err = errorOf(function() return inflate.raw(data) end)
  t:ok(err and err:find("inflate: " .. reason, 1, true), reason .. ": " .. tostring(err))
end

-- Bytes from fields {value, bits}, each written least significant bit first, as DEFLATE packs them. A Huffman code
-- goes most significant bit first: {code, bits, true}.
local function pack(fields)
  local out, byte, used = {}, 0, 0
  for _, f in ipairs(fields) do
    local value, bits, codeOrder = f[1], f[2], f[3]
    for i = 0, bits - 1 do
      local shift = codeOrder and bits - 1 - i or i
      byte = byte + math.floor(value / 2 ^ shift) % 2 * 2 ^ used
      used = used + 1
      if used == 8 then
        out[#out + 1] = string.char(byte)
        byte, used = 0, 0
      end
    end
  end
  if used > 0 then out[#out + 1] = string.char(byte) end
  return table.concat(out)
end

local FINAL, TYPE_FIXED, TYPE_DYNAMIC, PAD = { 1, 1 }, { 1, 2 }, { 2, 2 }, { 0, 16 }
-- fixed codes: the literal "a", length code 257 (a match of 3) and the end of the block
local A, LENGTH_3, END = { 145, 8, true }, { 1, 7, true }, { 0, 7, true }

-- A dynamic block's header with 257 literal and length codes, 1 distance code and code length codes for 16, 17, 18
-- and 0 (in that order) of these lengths.
local function dynamic(l16, l17, l18, l0)
  return { FINAL, TYPE_DYNAMIC, { 0, 5 }, { 0, 5 }, { 0, 4 }, { l16, 3 }, { l17, 3 }, { l18, 3 }, { l0, 3 } }
end

-- With every code length code 2 bits long, the codes are 0 = 00, 16 = 01, 17 = 10 and 18 = 11.
local function lengths(...)
  local fields = dynamic(2, 2, 2, 2)
  for _, f in ipairs({ ... }) do fields[#fields + 1] = f end
  fields[#fields + 1] = PAD
  return pack(fields)
end
local REPEAT, ZEROS = { 1, 2, true }, { 3, 2, true }   -- codes 16 (repeat the last length) and 18 (11 to 138 zeros)

return {
  a_hand_packed_block = function(t)
    t:eq(inflate.raw(pack({ FINAL, TYPE_FIXED, A, LENGTH_3, { 0, 5, true }, END })), "aaaa",
      "a, then 3 more from 1 back")
  end,
  stored_length_mismatch = function(t)
    fails(t, hex("0105 0000 00"), "stored length mismatch")
  end,
  stored_block_cut_short = function(t)
    fails(t, hex("0105 00fa ff68 65"), "input ends early")
  end,
  length_code_286 = function(t)
    fails(t, pack({ FINAL, TYPE_FIXED, { 198, 8, true }, PAD }), "invalid length code")
  end,
  -- the fixed distance code has 30 symbols, so 30 and 31 aren't codes at all
  distance_code_30 = function(t)
    fails(t, pack({ FINAL, TYPE_FIXED, A, LENGTH_3, { 30, 5, true }, PAD }), "invalid code")
  end,
  distance_too_far_back = function(t)
    fails(t, pack({ FINAL, TYPE_FIXED, A, LENGTH_3, { 1, 5, true }, PAD }), "distance too far back")
  end,
  bad_counts = function(t)
    fails(t, pack({ FINAL, TYPE_DYNAMIC, { 30, 5 }, { 0, 5 }, { 0, 4 }, PAD }), "bad counts")
  end,
  over_subscribed_code = function(t)
    local fields = dynamic(1, 1, 1, 1)
    fields[#fields + 1] = PAD
    fails(t, pack(fields), "over-subscribed code")
  end,
  -- only code length 0 has a code (0), so a 1 bit starts no code
  invalid_code = function(t)
    local fields = dynamic(0, 0, 0, 1)
    fields[#fields + 1] = { 65535, 16 }
    fails(t, pack(fields), "invalid code")
  end,
  repeat_with_no_first_length = function(t)
    fails(t, lengths(REPEAT, { 0, 2 }), "repeat with no first length")
  end,
  too_many_lengths = function(t)
    fails(t, lengths(ZEROS, { 127, 7 }, ZEROS, { 127, 7 }), "too many lengths")
  end,
  -- 138 zeros and 120 more fill all 258 lengths, leaving none for the end of the block
  no_end_of_block_code = function(t)
    fails(t, lengths(ZEROS, { 127, 7 }, ZEROS, { 109, 7 }), "no end-of-block code")
  end,
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
