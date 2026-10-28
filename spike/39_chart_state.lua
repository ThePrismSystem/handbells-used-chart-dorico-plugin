-- What the open scratch copy holds, for spike/39_chart_undo.py: each flow's title, note count and player count, and
-- every player's name. Read-only.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../"
local mine = here .. "lib/?.lua;" .. repo .. "tests/dorico/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("39_chart_state", function(p)
  local cases = require("cases")
  local dump = require("hbuc.dump")
  local textexport = require("hbuc.textexport")
  local doc = require("hbuc.dorico.doc")
  local ctx = cases.context(p)
  local score = ctx.app.currentScore
  local titles = textexport.flowTitles(doc.exportText(ctx.app, ctx.log, ctx.folders.temp, "state"))
  local flows = {}
  for n, f in ipairs(score.flows) do
    local notes = 0
    for _, s in ipairs(f.voiceStreams) do notes = notes + #dump.notes(doc.dumpOf(s)) end
    flows[n] = { title = titles[n] or "?", notes = notes, players = #f.players }
  end
  local names = {}
  for _, pl in ipairs(score.players) do names[#names + 1] = tostring(pl) end
  p:fact("flows", flows)
  p:fact("players", names)
end)
