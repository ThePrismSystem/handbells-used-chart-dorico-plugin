-- The overload signatures of the stream, flow and score methods not used yet. A bound method called with no
-- arguments fails with "No matching overload found, candidates: ..." and changes nothing. Read-only.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua"
for name in pairs(package.loaded) do
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

local function sig(obj, name)
  local ok, err = pcall(function() return obj[name](obj) end)
  if ok then return "returned without arguments" end
  return tostring(err):gsub("No matching overload found, candidates:\n", "")
end

probe.run("20_signatures", function(p)
  local app = DoApp.DoApp()
  local score = app.currentScore
  local flow = score.flows[1]
  local s = flow.voiceStreams[1]
  local out = {}
  for _, m in ipairs({ "copyRange", "copyRangeLinked", "moveRange", "splitStream", "joinBlocks", "addBlockInstance",
    "removeBlockInstance", "findBlockInstanceAtPoint", "deleteEventsInRange", "createTuplet", "createDynamicGroup",
    "createGraceNote" }) do
    out["stream." .. m] = sig(s, m)
  end
  local okT, t = pcall(function() return s.type end)
  out["stream.type"] = okT and tostring(t) or "?"
  local okV, v = pcall(function() return s.voiceDirection end)
  out["stream.voiceDirection"] = okV and tostring(v) or "?"
  local okE, et = pcall(function() return flow.elementTables end)
  out["flow.elementTables"] = okE and tostring(et) or tostring(et)
  p:fact("signatures", out)
end)
