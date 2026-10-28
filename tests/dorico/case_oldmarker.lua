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
  -- The marker is found in the dump, which gives a text event's text; the event to delete is then looked up by id in
  -- stream.events, which works in the chart flow (its streams hold only notes and texts).
  for _, s in ipairs(app.currentScore.flows[1].voiceStreams) do
    for _, ev in ipairs(doc.dumpOf(s).events) do
      if not old and ev.kind == "text" and marker.isMarker(ev.text) then
        old = (ev.text:gsub("^HBUC|2|", "HBUC|1|"):gsub("|[^|]*$", ""))
        for _, e in ipairs(s.events) do
          if e.id == ev.id then s:delete(e) end
        end
        doc.setTrue(s:createText(DoCore.RhythmicLength(0), DoCore.RhythmicLength(1), old), "kTextHide")
      end
    end
  end
  p:fact("oldMarker", old or "")
  local m = old and marker.decode(old)
  p:check("the marker is a version 1 one now", m and m.version == "1" and m.restore.flowBreakBehaviour == nil, old)
  local markers = {}
  for _, s in ipairs(app.currentScore.flows[1].voiceStreams) do
    for _, ev in ipairs(doc.dumpOf(s).events) do
      if ev.kind == "text" and marker.isMarker(ev.text) then markers[#markers + 1] = ev.text end
    end
  end
  p:check("the old marker is the only one", #markers == 1 and markers[1] == old, table.concat(markers, " / "))
end)
