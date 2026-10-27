-- Which rest events are in the chart flow's voice streams, and where? Read-only.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua"
for name in pairs(package.loaded) do
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("27_rests", function(p)
  local chart = DoApp.DoApp().currentScore.flows[1]
  local rows = {}
  for i, s in ipairs(chart.voiceStreams) do
    local d = s:dump()
    for line in (d .. "\n"):gmatch("(.-)\n") do
      if line:find("Rest", 1, true) then rows[#rows + 1] = i .. " (" .. s.id .. "): " .. line end
    end
    rows[#rows + 1] = i .. " (" .. s.id .. ") head: " .. d:sub(1, 300):gsub("\n", " | ")
  end
  p:fact("rows", rows)
end)
