-- Raw DEFLATE (RFC 1951), for reading score.dtn out of a saved copy of the project (hbuc.zip), since Dorico's Lua
-- has no zlib. It is written for speed: a real score's score.dtn runs to a few megabytes, read before the dialog
-- opens.
local inflate = {}

local byte, char, floor = string.byte, string.char, math.floor

local POW2 = {}
for i = 0, 31 do POW2[i] = 2 ^ i end

-- Codes up to this long decode with one table lookup; longer ones (rare, being the least frequent symbols) bit by
-- bit.
local FAST = 9
local FAST_SIZE = POW2[FAST]

local LENGTH_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131,
  163, 195, 227, 258 }
local LENGTH_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DIST_BASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049,
  3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DIST_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CODE_LENGTH_ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

local WINDOW = 32768
-- The output is kept as byte values and turned into strings in pieces; the last WINDOW values stay behind for
-- back-references. A bigger buffer means fewer of those moves.
local BUFFER = 262144
local PIECE = 4096

local function fail(reason)
  error("inflate: " .. reason, 0)
end

-- A canonical Huffman code from its code lengths (lengths[0..n-1]): the per-length counts and length-ordered symbols
-- the bit-by-bit decode walks, and a FAST-bit table whose entries are symbol * 16 + length.
local function build(lengths, n)
  local count = {}
  for len = 0, 15 do count[len] = 0 end
  for s = 0, n - 1 do count[lengths[s]] = count[lengths[s]] + 1 end
  local left = 1
  for len = 1, 15 do
    left = left * 2 - count[len]
    if left < 0 then fail("over-subscribed code") end
  end
  local offset, symbol = { [1] = 0 }, {}
  for len = 1, 14 do offset[len + 1] = offset[len] + count[len] end
  local nextCode, code = {}, 0
  count[0] = 0
  for len = 1, 15 do
    code = (code + count[len - 1]) * 2
    nextCode[len] = code
  end
  local fast = {}
  for s = 0, n - 1 do
    local len = lengths[s]
    if len > 0 then
      symbol[offset[len]] = s
      offset[len] = offset[len] + 1
      local c = nextCode[len]
      nextCode[len] = c + 1
      if len <= FAST then
        -- bits arrive least significant first, so the table is indexed by the code reversed
        local rev = 0
        for _ = 1, len do
          rev = rev * 2 + c % 2
          c = floor(c / 2)
        end
        for i = rev, FAST_SIZE - 1, POW2[len] do fast[i] = s * 16 + len end
      end
    end
  end
  return { count = count, symbol = symbol, fast = fast }
end

local FIXED_LITERALS, FIXED_DISTANCES
do
  local lengths = {}
  for s = 0, 143 do lengths[s] = 8 end
  for s = 144, 255 do lengths[s] = 9 end
  for s = 256, 279 do lengths[s] = 7 end
  for s = 280, 287 do lengths[s] = 8 end
  FIXED_LITERALS = build(lengths, 288)
  lengths = {}
  for s = 0, 29 do lengths[s] = 5 end
  FIXED_DISTANCES = build(lengths, 30)
end

-- The decoded bytes of data from byte start (default 1) through the final block.
function inflate.raw(data, start)
  local pos, size = start or 1, #data
  local bitbuf, bitcnt = 0, 0
  local buf, n, parts = {}, 1, {}

  local function need(bits)
    while bitcnt < bits do
      local b = byte(data, pos)
      if not b then fail("input ends early") end
      bitbuf = bitbuf + b * POW2[bitcnt]
      pos = pos + 1
      bitcnt = bitcnt + 8
    end
  end

  local function bitsOf(count)
    if count == 0 then return 0 end
    need(count)
    local p = POW2[count]
    local v = bitbuf % p
    bitbuf = (bitbuf - v) / p
    bitcnt = bitcnt - count
    return v
  end

  local function decode(h)
    -- fill as far as the table reaches, without failing near the end of the input
    while bitcnt < FAST and pos <= size do
      bitbuf = bitbuf + byte(data, pos) * POW2[bitcnt]
      pos = pos + 1
      bitcnt = bitcnt + 8
    end
    local e = h.fast[bitbuf % FAST_SIZE]
    if e then
      local len = e % 16
      if len > bitcnt then fail("input ends early") end
      local p = POW2[len]
      bitbuf = (bitbuf - bitbuf % p) / p
      bitcnt = bitcnt - len
      return (e - len) / 16
    end
    local count, symbol = h.count, h.symbol
    local code, first, index = 0, 0, 0
    for len = 1, 15 do
      code = code + bitsOf(1)
      local c = count[len]
      if code - c < first then return symbol[index + code - first] end
      index = index + c
      first = (first + c) * 2
      code = code * 2
    end
    fail("invalid code")
  end

  local function flush(keep)
    local last = n - 1 - keep
    for i = 1, last, PIECE do
      parts[#parts + 1] = char(unpack(buf, i, math.min(i + PIECE - 1, last)))
    end
    for i = 1, keep do buf[i] = buf[last + i] end
    n = keep + 1
  end

  local function codes(literals, distances)
    while true do
      local s = decode(literals)
      if s < 256 then
        buf[n] = s
        n = n + 1
      elseif s == 256 then
        return
      else
        s = s - 256
        if s > 29 then fail("invalid length code") end
        local length = LENGTH_BASE[s] + bitsOf(LENGTH_EXTRA[s])
        local d = decode(distances) + 1
        if d > 30 then fail("invalid distance code") end
        local dist = DIST_BASE[d] + bitsOf(DIST_EXTRA[d])
        if dist >= n then fail("distance too far back") end
        local from = n - dist
        for i = 0, length - 1 do buf[n + i] = buf[from + i] end
        n = n + length
      end
      if n > BUFFER then flush(WINDOW) end
    end
  end

  local function dynamic()
    local nlen = bitsOf(5) + 257
    local ndist = bitsOf(5) + 1
    local ncode = bitsOf(4) + 4
    if nlen > 286 or ndist > 30 then fail("bad counts") end
    local lengths = {}
    for i = 0, 18 do lengths[i] = 0 end
    for i = 1, ncode do lengths[CODE_LENGTH_ORDER[i]] = bitsOf(3) end
    local lencode = build(lengths, 19)
    lengths = {}
    local i = 0
    while i < nlen + ndist do
      local s = decode(lencode)
      if s < 16 then
        lengths[i] = s
        i = i + 1
      else
        local value, rep = 0
        if s == 16 then
          if i == 0 then fail("repeat with no first length") end
          value, rep = lengths[i - 1], 3 + bitsOf(2)
        elseif s == 17 then
          rep = 3 + bitsOf(3)
        else
          rep = 11 + bitsOf(7)
        end
        if i + rep > nlen + ndist then fail("too many lengths") end
        for _ = 1, rep do
          lengths[i] = value
          i = i + 1
        end
      end
    end
    if lengths[256] == 0 then fail("no end-of-block code") end
    local lit, dist = {}, {}
    for s = 0, nlen - 1 do lit[s] = lengths[s] end
    for s = 0, ndist - 1 do dist[s] = lengths[nlen + s] end
    return build(lit, nlen), build(dist, ndist)
  end

  repeat
    local final = bitsOf(1)
    local kind = bitsOf(2)
    if kind == 0 then
      -- stored: the rest of this byte is padding, then LEN and its complement. A table lookup may have read whole
      -- bytes past it, which go back.
      pos = pos - floor(bitcnt / 8)
      bitbuf, bitcnt = 0, 0
      if pos + 3 > size then fail("input ends early") end
      local a, b, c, d = byte(data, pos, pos + 3)
      local len = a + b * 256
      if len ~= 65535 - (c + d * 256) then fail("stored length mismatch") end
      pos = pos + 4
      if pos + len - 1 > size then fail("input ends early") end
      for k = 0, len - 1 do
        buf[n] = byte(data, pos + k)
        n = n + 1
        if n > BUFFER then flush(WINDOW) end
      end
      pos = pos + len
    elseif kind == 1 then
      codes(FIXED_LITERALS, FIXED_DISTANCES)
    elseif kind == 2 then
      codes(dynamic())
    else
      fail("invalid block type")
    end
  until final == 1
  flush(0)
  return table.concat(parts)
end

return inflate
