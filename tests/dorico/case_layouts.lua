-- The full score's layout id and the id of the part holding the player of the first flow's first voice (the note
-- case_colour colours), on the scratch copy that is open. Read-only.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../../"
local mine = here .. "lib/?.lua;" .. repo .. "spike/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
-- first, whatever came before: the plug-in's entry file (test_run.py's RealDialog) leaves its install on the
-- path, and an older install there would be loaded instead
if package.path:sub(1, #mine + 1) ~= mine .. ";" then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("case_layouts", function(p)
  -- required here, not above: a module that fails to load is then reported, and the copy closed
  local chartlayout = require("hbuc.chartlayout")
  local doc = require("hbuc.dorico.doc")
  local score = DoApp.DoApp().currentScore
  local layouts, allKeys = doc.layouts(score), {}
  for _, pl in ipairs(score.players) do allKeys[#allKeys + 1] = doc.playerKey(pl) end
  p:fact("fullLayout", chartlayout.fullScoreLayout(layouts, allKeys))
  local key = doc.voiceOwners(score.flows[1])[1].key
  for _, l in ipairs(layouts) do
    if #l.keys == 1 and l.keys[1] == key then p:fact("firstPartLayout", l.id) end
  end
  p:check("found the part", p.facts.firstPartLayout ~= nil)
end)
