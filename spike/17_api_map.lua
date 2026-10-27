-- Write the bound API's member lists (every registry table's keys, plus DoCore/DoScore statics) to
-- <run dir>/api-map.txt for searching. Read-only.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua"
for name in pairs(package.loaded) do
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

local function keysOf(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = tostring(k) end
  table.sort(ks)
  return table.concat(ks, " ")
end

probe.run("17_api_map", function(p)
  local out = {}
  local reg = debug.getregistry()
  local idx = {}
  for k in pairs(reg) do idx[#idx + 1] = k end
  table.sort(idx, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(idx) do
    local v = reg[k]
    if type(v) == "table" then out[#out + 1] = "R." .. tostring(k) .. " = " .. keysOf(v):sub(1, 4000) end
  end
  -- luabind's class_names, where the build has it
  local okN, names = pcall(class_names) -- luacheck: ignore 113
  if okN and type(names) == "table" then out[#out + 1] = "class_names = " .. table.concat(names, " ") end
  for _, g in ipairs({ "DoCore", "DoScore", "DoApp", "DoUI" }) do
    local t = rawget(_G, g)
    if type(t) == "table" then
      for name, cls in pairs(t) do
        local line = g .. "." .. tostring(name) .. " : " .. type(cls)
        local mt = debug.getmetatable(cls)
        if mt then line = line .. " mt{" .. keysOf(mt) .. "}" end
        if type(cls) == "table" then line = line .. " {" .. keysOf(cls):sub(1, 2000) .. "}" end
        out[#out + 1] = line
      end
    end
  end
  local f = assert(io.open(probe.runDir .. "api-map.txt", "wb"))
  f:write(table.concat(out, "\n"))
  f:close()
  p:fact("lines", #out)
end)
