-- score.dtn bytes for tests (hbuc.dtn has the layout): from tables of names, values and records, or from a nested
-- {name, value, {children}} description.
local build = {}

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

-- records: {tag, name index, value index, child ids (for a tag with the 2 bit set)}
function build.encode(names, values, records)
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

-- root: {name, value (or nil), children (or nil)}; ids are given in the order Dorico writes them, parents first.
function build.tree(root)
  local names, values, nameIndex, valueIndex, records = {}, { "" }, {}, { [""] = 0 }, {}
  local function index(list, map, s)
    if map[s] == nil then
      list[#list + 1] = s
      map[s] = #list - 1
    end
    return map[s]
  end
  local function add(node)
    local id = #records
    local record = { 0x20, index(names, nameIndex, node[1]), index(values, valueIndex, node[2] or "") }
    records[id + 1] = record
    if node[3] then
      record[1], record[4] = 0x22, {}
      for _, kid in ipairs(node[3]) do table.insert(record[4], add(kid)) end
    end
    return id
  end
  add(root)
  return build.encode(names, values, records)
end

return build
