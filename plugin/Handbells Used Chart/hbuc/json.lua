-- Minimal JSON for Lua 5.2: encode with sorted object keys (stable output), decode to tables.
-- A table with keys 1..n (n >= 1) is an array; any other table, including {}, is an object.
local json = {}

json.null = setmetatable({}, { __tostring = function() return "null" end })

local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encodeString(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return escapes[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function isArray(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  if n == 0 then return false end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true
end

local function encode(v, seen)
  local kind = type(v)
  if v == json.null or v == nil then
    return "null"
  elseif kind == "boolean" then
    return tostring(v)
  elseif kind == "number" then
    if v ~= v or v == math.huge or v == -math.huge then error("json: cannot encode " .. tostring(v)) end
    -- %.0f, not %d: Lua 5.2 on Windows formats %d through a 32-bit C long
    if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return string.format("%.0f", v) end
    return string.format("%.17g", v)
  elseif kind == "string" then
    return encodeString(v)
  elseif kind == "table" then
    if seen[v] then error("json: cycle") end
    seen[v] = true
    local out = {}
    if isArray(v) then
      for i = 1, #v do out[i] = encode(v[i], seen) end
      seen[v] = nil
      return "[" .. table.concat(out, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do
      local kt = type(k)
      if kt ~= "string" and kt ~= "number" then error("json: cannot encode a " .. kt .. " key") end
      keys[#keys + 1] = tostring(k)
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local val = v[k]
      if val == nil then val = v[tonumber(k)] end
      out[#out + 1] = encodeString(k) .. ":" .. encode(val, seen)
    end
    seen[v] = nil
    return "{" .. table.concat(out, ",") .. "}"
  end
  return encodeString(tostring(v))
end

function json.encode(v)
  return encode(v, {})
end

local function utf8char(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40) end
  if cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
  return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40,
    0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

function json.decode(s)
  local pos = 1
  local function fail(msg) error("json: " .. msg .. " at position " .. pos, 0) end
  local function skip() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
  local value

  local function str()
    pos = pos + 1
    local parts = {}
    while true do
      local c = s:sub(pos, pos)
      if c == "" then fail("unterminated string") end
      if c == '"' then pos = pos + 1; break end
      if c == "\\" then
        local e = s:sub(pos + 1, pos + 1)
        local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
        if map[e] then
          parts[#parts + 1] = map[e]; pos = pos + 2
        elseif e == "u" then
          local hex = s:sub(pos + 2, pos + 5)
          if not hex:match("^%x%x%x%x$") then fail("bad \\u escape") end
          local cp = tonumber(hex, 16)
          pos = pos + 6
          if cp >= 0xD800 and cp <= 0xDBFF and s:sub(pos, pos + 1) == "\\u" then
            local lo = tonumber(s:sub(pos + 2, pos + 5), 16)
            if lo and lo >= 0xDC00 and lo <= 0xDFFF then
              cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
              pos = pos + 6
            end
          end
          parts[#parts + 1] = utf8char(cp)
        else
          fail("bad escape")
        end
      else
        local stop = s:find('["\\]', pos) or #s + 1
        parts[#parts + 1] = s:sub(pos, stop - 1)
        pos = stop
      end
    end
    return table.concat(parts)
  end

  function value()
    skip()
    local c = s:sub(pos, pos)
    if c == "{" then
      pos = pos + 1
      local obj = {}
      skip()
      if s:sub(pos, pos) == "}" then pos = pos + 1; return obj end
      while true do
        skip()
        if s:sub(pos, pos) ~= '"' then fail("expected key") end
        local k = str()
        skip()
        if s:sub(pos, pos) ~= ":" then fail("expected ':'") end
        pos = pos + 1
        obj[k] = value()
        skip()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == "}" then return obj end
        if d ~= "," then fail("expected ',' or '}'") end
      end
    elseif c == "[" then
      pos = pos + 1
      local arr = {}
      skip()
      if s:sub(pos, pos) == "]" then pos = pos + 1; return arr end
      while true do
        arr[#arr + 1] = value()
        skip()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == "]" then return arr end
        if d ~= "," then fail("expected ',' or ']'") end
      end
    elseif c == '"' then
      return str()
    elseif s:sub(pos, pos + 3) == "true" then
      pos = pos + 4; return true
    elseif s:sub(pos, pos + 4) == "false" then
      pos = pos + 5; return false
    elseif s:sub(pos, pos + 3) == "null" then
      pos = pos + 4; return json.null
    else
      local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      if not num or num == "" or num == "-" then fail("unexpected character '" .. c .. "'") end
      local n = tonumber(num)
      if n == nil then fail("malformed number '" .. num .. "'") end
      pos = pos + #num
      return n
    end
  end

  local result = value()
  skip()
  if pos <= #s then fail("trailing characters") end
  return result
end

return json
