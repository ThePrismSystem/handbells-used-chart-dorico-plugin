-- Do a saved copy's note events line up with the dumps? On a scratch copy of a real project, driven by
-- spike/54_real_map.py: every voice stream's notes from its dump ({flowId, id, pos, spelling, grace}), which notes
-- list kNoteheadSetOverride where Lua can list the stream's events, and app:save(score, args.file) after reading.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../"
local mine = here .. "lib/?.lua;" .. repo .. "tests/dorico/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("54_real_map", function(p)
  local dump = require("hbuc.dump")
  local doc = require("hbuc.dorico.doc")
  local app = DoApp.DoApp()
  local notes, listed, unlisted = {}, {}, 0
  local streamsRead, streamsThrew = 0, 0
  for _, flow in ipairs(app.currentScore.flows) do
    for _, s in ipairs(flow.voiceStreams) do
      for _, n in ipairs(dump.notes(doc.dumpOf(s))) do
        notes[#notes + 1] = { flowId = flow.id, id = n.id, pos = n.pos, spelling = n.spelling, grace = n.grace }
      end
      local ok, events = pcall(function() return s.events end)
      if ok then
        streamsRead = streamsRead + 1
        for _, e in ipairs(events) do
          local text = tostring(e)
          if text:match("^kNoteEvent") or text:match("^kGraceNoteEvent") then
            local has = false
            for _, name in ipairs(e.propertyTable:getPropertyNames()) do
              if name == "kNoteheadSetOverride" then has = true end
            end
            if has then listed[#listed + 1] = e.id else unlisted = unlisted + 1 end
          end
        end
      else
        streamsThrew = streamsThrew + 1
      end
    end
  end
  p:fact("notes", notes)
  p:fact("listedIds", listed)
  p:fact("unlistedCount", unlisted)
  p:fact("streamsRead", streamsRead)
  p:fact("streamsThrew", streamsThrew)
  local t0 = os.clock()
  local okSave, saved = pcall(function() return app:save(app.currentScore, p.args.file) end)
  p:fact("saveSeconds", os.clock() - t0)
  p:check("app:save", okSave and saved == true, tostring(saved))
end)
