-- Post-import pass for the fixture: apply each heads.json notehead set and colour.
-- args: headsPath
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua;" .. here .. "../spike/lib/?.lua"
for name in pairs(package.loaded) do -- Dorico keeps one Lua state between runs: reload our modules
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")
local json = require("json")
local fixtureindex = require("fixtureindex")

local function readJson(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return json.decode(s)
end

probe.run("apply_heads", function(p)
  local app = DoApp.DoApp()
  local flow = app.currentScore.flows[1]
  local heads = readJson(p.args.headsPath)
  local index = fixtureindex.build(app, flow)
  local ctx = DoCore.PropertyContext()
  local failed, applied = {}, 0
  for _, h in ipairs(heads) do
    local found = fixtureindex.lookup(index, h)
    local label = h.player .. " bar " .. h.bar .. " " .. h.written
    if not found then
      failed[#failed + 1] = label .. ": not found"
    else
      local pt = found.event.propertyTable
      if h.noteheadSet ~= "noteheadset.default" then
        if not pt:set("kNoteheadSetOverride", DoCore.Variant.createString(h.noteheadSet), ctx) then
          failed[#failed + 1] = label .. ": notehead set refused"
        end
      end
      if h.colour ~= json.null and h.colour then
        if not pt:set("kEventColour", DoCore.Variant.createString(h.colour), ctx) then
          failed[#failed + 1] = label .. ": colour refused"
        end
      end
      applied = applied + 1
    end
  end
  p:fact("applied", applied)
  p:check("every notehead and colour set", #failed == 0, table.concat(failed, "; "))
end)
