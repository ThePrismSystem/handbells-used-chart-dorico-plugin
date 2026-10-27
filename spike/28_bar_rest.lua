-- An update left an explicit bar rest in a chart voice. Does selecting it and running Edit.RemoveRests
-- (args.how = "removerests") or deleting it from Lua (args.how = "delete") take it away, with no implicit rest
-- showing in its place? Scratch copy only.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua"
for name in pairs(package.loaded) do
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

local function restLines(flow)
  local out = {}
  for _, s in ipairs(flow.voiceStreams) do
    for line in (s:dump() .. "\n"):gmatch("(.-)\n") do
      if line:find("RestEvent", 1, true) then out[#out + 1] = s.id .. ": " .. line end
    end
  end
  return out
end

probe.run("28_bar_rest", function(p)
  local app = DoApp.DoApp()
  local chart = app.currentScore.flows[1]
  p:fact("before", restLines(chart))
  for _, s in ipairs(chart.voiceStreams) do
    local d = s:dump()
    local id = tonumber(d:match("kBarRestEvent %(id:(%d+)%)"))
    if id then
      if p.args.how == "delete" then
        for _, e in ipairs(s.events) do
          if e.id == id then s:delete(e) end
        end
      else
        local block = tonumber(d:match("Start block id: (%d+)")) - 1000
        app:doCommand("Edit.SelectNone")
        app:doCommand("EventEdit.Select?FlowID=" .. chart.id .. "&EventID=" .. id .. "&EventBlockID=" .. block)
        app:doCommand("Edit.RemoveRests")
        app:doCommand("Edit.SelectNone")
      end
    end
  end
  local after = restLines(app.currentScore.flows[1])
  p:fact("after", after)
  p:check("no rest events left", #after == 0, #after)
end)
