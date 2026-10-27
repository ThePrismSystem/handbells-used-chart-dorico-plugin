-- Can the notes of a flow whose voice streams .events cannot list (lyrics, slurs, techniques) be read by
-- copying them, filtered to notes and chords, into a new flow (which holds every player) and reading that flow
-- instead? Compares note counts per instrument with the source dumps. Scratch copy only.
--   args.flowIndex: which flow to read (default 1)
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua"
for name in pairs(package.loaded) do
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

local RL = function(n) return DoCore.RhythmicLength(n) end

local function flowById(app, id)
  for _, f in ipairs(app.currentScore.flows) do if f.id == id then return f end end
end

local function dumpOf(s)
  local ok, d = pcall(function() return s:dump() end)
  return ok and d or ""
end

local function firstEventId(d)
  return tonumber(d:match(": k%a+ %(id:(%d+)%)"))
end

local function blockId(d)
  return tonumber(d:match("Start block id: (%d+)")) - 1000
end

local function noteCount(d)
  local n = 0
  for _ in d:gmatch(": kNoteEvent %(id:") do n = n + 1 end
  for _ in d:gmatch(": kGraceNoteEvent %(id:") do n = n + 1 end
  return n
end

probe.run("22_paste_read", function(p)
  local app = DoApp.DoApp()
  local score = app.currentScore
  local ctx = DoCore.PropertyContext()
  local music = score.flows[p.args.flowIndex or 1]
  local musicId = music.id

  -- per instrument: notes in the source, from the dumps
  local want, fis = {}, music.instruments
  for i, s in ipairs(music.voiceStreams) do
    local id = fis[i] and fis[i].id or -1
    want[id] = (want[id] or 0) + noteCount(dumpOf(s))
  end
  p:fact("sourceNotesByInstrument", want)

  -- the scratch flow, holding every player
  local before = {}
  for _, f in ipairs(score.flows) do before[f.id] = true end
  app:doCommand("Project.Flow.New")
  local scratchId
  for _, f in ipairs(app.currentScore.flows) do if not before[f.id] then scratchId = f.id end end
  if not p:check("new flow", scratchId ~= nil) then return end

  -- select the music flow's whole range on every staff, keep notes and chords, copy
  local t0 = os.clock()
  app:doCommand("Edit.SelectNone")
  music = flowById(app, musicId)
  local topD = dumpOf(music.voiceStreams[1])
  app:doCommand("EventEdit.Select?FlowID=" .. musicId .. "&EventID=" .. firstEventId(topD) .. "&EventBlockID=" .. blockId(topD))
  app:doCommand("EventEdit.NavigateDownExtendBottom")
  app:doCommand("Edit.SelectToStartOfFlow")
  app:doCommand("Edit.SelectAtEndOfFlow")
  app:doCommand("Filter.NotesAndChords")
  app:doCommand("Edit.Copy")

  -- paste at the start of the scratch flow's top staff, on a temporary note there
  local scratch = flowById(app, scratchId)
  local top = scratch.voiceStreams[1]
  local temp = top:createNote(RL(0), RL(1), DoCore.MIDIPitchWithSpelling.fromString("C5"))
  local td = dumpOf(top)
  app:doCommand("Edit.SelectNone")
  app:doCommand("EventEdit.Select?FlowID=" .. scratchId .. "&EventID=" .. temp.id .. "&EventBlockID=" .. blockId(td))
  app:doCommand("Edit.Paste")
  app:doCommand("Edit.SelectNone")
  p:fact("secondsToCopyAndPaste", os.clock() - t0)

  -- read the scratch flow through .events
  scratch = flowById(app, scratchId)
  local got, heads, colours, unreadable = {}, {}, {}, 0
  local sfis = scratch.instruments
  for i, s in ipairs(scratch.voiceStreams) do
    local id = sfis[i] and sfis[i].id or -1
    local ok, list = pcall(function() return s.events end)
    if not ok then
      unreadable = unreadable + 1
    else
      for _, e in ipairs(list) do
        local okT, t = pcall(tostring, e)
        if okT and (t:find("kNoteEvent", 1, true) or t:find("kGraceNoteEvent", 1, true)) then
          got[id] = (got[id] or 0) + 1
          local h = tostring(e.propertyTable:get("kNoteheadSetOverride", ctx))
          local c = tostring(e.propertyTable:get("kEventColour", ctx))
          heads[h] = (heads[h] or 0) + 1
          colours[c] = (colours[c] or 0) + 1
        end
      end
    end
  end
  p:fact("pastedNotesByInstrument", got)
  p:fact("heads", heads)
  p:fact("colours", colours)
  p:fact("scratchVoiceStreams", #scratch.voiceStreams)
  p:check("every pasted stream is readable", unreadable == 0, unreadable)
  local same = true
  for id, n in pairs(want) do if (got[id] or 0) ~= n then same = false end end
  p:check("pasted notes match the source per instrument", same)
end)
