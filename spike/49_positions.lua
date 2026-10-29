-- Every note's position as the dumps give it, to compare with a MusicXML export (spike/49_positions.py). Read-only:
-- per flow, "<player name>|<pos>|<sounding spelling>|<grace>" for each dumped note.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../"
local mine = here .. "lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("49_positions", function(p)
  local doc = require("hbuc.dorico.doc")
  local score = DoApp.DoApp().currentScore
  local nameOf = {}
  for _, pl in ipairs(score.players) do
    for _, ins in ipairs(pl.instruments) do nameOf[ins.id] = tostring(pl) end
  end
  local flows = {}
  for i, flow in ipairs(score.flows) do
    local notes = {}
    for _, o in ipairs(doc.voiceOwners(flow)) do
      for _, ev in ipairs(doc.dumpOf(o.stream).events) do
        if (ev.kind == "note" or ev.kind == "grace") and ev.spelling then
          notes[#notes + 1] = table.concat({ nameOf[o.key] or "?", string.format("%.6f", ev.pos or -1), ev.spelling,
            tostring(ev.kind == "grace") }, "|")
        end
      end
    end
    flows[#flows + 1] = { number = i, id = flow.id, notes = notes }
  end
  p:fact("flows", flows)
end)
