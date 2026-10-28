-- Turns the chart's marker into a version 1 one, as charts drawn before the flow-break option carry: the same text
-- without its flow-break value. Scratch copy only.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../../"
local mine = here .. "lib/?.lua;" .. repo .. "spike/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("case_oldmarker", function(p)
  -- required here, not above: a module that fails to load is then reported, and the copy closed
  local doc = require("hbuc.dorico.doc")
  local marker = require("hbuc.marker")
  local app = DoApp.DoApp()
  local old
  -- the chart flow is first, and its streams hold only notes and texts, so .events works there
  for _, s in ipairs(app.currentScore.flows[1].voiceStreams) do
    for _, e in ipairs(s.events) do
      local ok, text = pcall(function() return e.text end)
      if not old and ok and marker.isMarker(text) then
        old = (text:gsub("^HBUC|2|", "HBUC|1|"):gsub("|[^|]*$", ""))
        s:delete(e)
        doc.setTrue(s:createText(DoCore.RhythmicLength(0), DoCore.RhythmicLength(1), old), "kTextHide")
      end
    end
  end
  p:fact("oldMarker", old or "")
  local m = old and marker.decode(old)
  p:check("the marker is a version 1 one now", m and m.version == "1" and m.restore.flowBreakBehaviour == nil, old)
end)
