-- Gives the fixture's first player nothing to play in flow 1 before a read: deletes every event in its voices there.
-- In a run of its own, since the paste route's Edit.Undo would take back an edit made in the reading run.
--   args.topOnly: empty only its first voice (the treble staff of its grand staff) and leave the bass
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../../"
local mine = here .. "lib/?.lua;" .. repo .. "spike/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("case_tacet", function(p)
  -- required here, not above: a module that fails to load is then reported, and the copy closed
  local cases = require("cases")
  local dump = require("hbuc.dump")
  local doc = require("hbuc.dorico.doc")
  local score = cases.context(p).app.currentScore
  local key = doc.playerKey(score.players[1])
  local emptied, left = 0, 0
  for _, o in ipairs(doc.voiceOwners(score.flows[1])) do
    if o.key == key then
      if emptied == 0 or not p.args.topOnly then
        o.stream:deleteEventsInRange(DoCore.RhythmicLength(0), DoCore.RhythmicLength(1000))
        emptied = emptied + 1
        p:check("voice " .. o.stream.id .. " is empty", dump.firstEventId(doc.dumpOf(o.stream)) == nil)
      else
        left = left + #dump.notes(doc.dumpOf(o.stream))
      end
    end
  end
  p:fact("emptied", emptied)
  p:fact("notesLeft", left)
  if p.args.topOnly then p:check("the player's other voices still have notes", left > 0, left) end
end)
