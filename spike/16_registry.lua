-- What members do the bound classes really have? luabind keeps each class's methods in a Lua table; scan the
-- registry (and metatables of live objects) for tables holding known member names, and list every key of
-- each. Read-only.
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

local WANT = { "createNote", "dump", "propertyTable", "voiceStreams", "doCommand", "addPlayer", "getPropertyNames" }

probe.run("16_registry", function(p)
  local found, seen = {}, {}
  local function visit(t, path, depth)
    if type(t) ~= "table" or seen[t] or depth > 4 then return end
    seen[t] = true
    for _, w in ipairs(WANT) do
      local ok, v = pcall(rawget, t, w)
      if ok and v ~= nil then
        found[#found + 1] = { path = path, hit = w, keys = keysOf(t):sub(1, 3000) }
        break
      end
    end
    for k, v in pairs(t) do
      if type(v) == "table" then visit(v, path .. "." .. tostring(k), depth + 1) end
      if type(v) == "userdata" then
        local mt = debug.getmetatable(v)
        if mt then visit(mt, path .. "." .. tostring(k) .. "<mt>", depth + 1) end
      end
    end
  end
  visit(debug.getregistry(), "R", 0)
  local app = DoApp.DoApp()
  local s = app.currentScore.flows[1].voiceStreams[1]
  local mt = debug.getmetatable(s)
  p:fact("streamMetatableKeys", mt and keysOf(mt) or "none")
  if mt then
    for k, v in pairs(mt) do
      if type(v) == "table" then p:fact("streamMt." .. tostring(k), keysOf(v):sub(1, 3000)) end
    end
  end
  p:fact("found", found)
  local globals = {}
  for k, v in pairs(_G) do globals[#globals + 1] = tostring(k) .. ":" .. type(v) end
  table.sort(globals)
  p:fact("globals", table.concat(globals, " "))
  local mods = {}
  for _, g in ipairs({ "DoApp", "DoCore", "DoUI" }) do
    local t = rawget(_G, g)
    if type(t) == "table" then mods[g] = keysOf(t) end
  end
  p:fact("modules", mods)
end)
