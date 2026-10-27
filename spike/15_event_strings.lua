-- Which events in a real score have no tostring ("Not implemented"), and does stream:dump() still describe
-- them? Read-only. Also compares flow.instruments with voiceStreams one-for-one.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua"
for name in pairs(package.loaded) do
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("15_event_strings", function(p)
  local app = DoApp.DoApp()
  local score = app.currentScore
  p:fact("openScoreID", score.openScoreID)
  local ctx = DoCore.PropertyContext()
  local flows = {}
  for fi, flow in ipairs(score.flows) do
    if fi > 3 then break end
    local failures, kinds, total = {}, {}, 0
    local badStreams = {}
    for _, s in ipairs(flow.voiceStreams) do
      local okE, list = pcall(function() return s.events end)
      if not okE then
        local okD, d = pcall(function() return s:dump() end)
        local seen = {}
        if okD then
          for k in d:gmatch(": (k%a+) %(id:") do seen[k] = (seen[k] or 0) + 1 end
        end
        local parts = {}
        for k, n in pairs(seen) do parts[#parts + 1] = k .. "=" .. n end
        table.sort(parts)
        badStreams[#badStreams + 1] = { stream = s.id, dumpOk = okD, dumpKinds = table.concat(parts, ","),
          dumpHead = okD and d:sub(1, 600) or tostring(d):sub(1, 120) }
        list = {}
      end
      for _, e in ipairs(list) do
        total = total + 1
        local ok, t = pcall(tostring, e)
        if ok then
          local k = t:match("^(k%a+)") or "?"
          kinds[k] = (kinds[k] or 0) + 1
        elseif #failures < 8 then
          local okN, names = pcall(function() return e.propertyTable:getPropertyNames() end)
          local okId, id = pcall(function() return e.id end)
          local okPos, pos = pcall(function() return tostring(e.position) end)
          failures[#failures + 1] = { stream = s.id, id = okId and id or "?", pos = okPos and pos or "?",
            props = okN and table.concat(names, ",") or "?",
            pitch = (function() local o, v = pcall(function() return tostring(e.propertyTable:get("kNotePitch", ctx)) end) return o and v or "?" end)() }
        end
      end
    end
    local dumpLines = {}
    for _, s in ipairs(flow.voiceStreams) do
      local okD, d = pcall(function() return s:dump() end)
      if not okD then dumpLines[#dumpLines + 1] = "dump failed: " .. tostring(d):sub(1, 100) end
    end
    local fis = flow.instruments
    local fiIds = {}
    for i, f in ipairs(fis) do fiIds[i] = f.id end
    local vsIds = {}
    for i, s in ipairs(flow.voiceStreams) do vsIds[i] = s.id end
    flows[#flows + 1] = { flow = flow.id, badStreams = badStreams, total = total, kinds = kinds, failures = failures, dumpFailures = dumpLines,
      fiIds = table.concat(fiIds, ","), voiceIds = table.concat(vsIds, ","), staves = #flow.staveStreams }
  end
  p:fact("flows", flows)
  local pls = {}
  for _, pl in ipairs(score.players) do
    local ids = {}
    for _, ins in ipairs(pl.instruments) do ids[#ids + 1] = ins.id end
    pls[#pls + 1] = tostring(pl) .. "=" .. table.concat(ids, "/")
  end
  p:fact("players", table.concat(pls, "; "))
end)
