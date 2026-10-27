-- Read a flow's notes (with noteheads and colours) by pasting them, filtered to notes and chords, into a
-- scratch flow holding only that flow's players, then take the scratch flow away again with two Edit.Undo (the
-- paste, then Project.Flow.New), leaving the project as it was. Scratch copy only.
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

local function blockId(d)
  return tonumber(d:match("Start block id: (%d+)")) - 1000
end

-- "<instrument id>:<spelling>" for every note and grace note in a flow's dumps, sorted
local function noteKeys(flow)
  local keys, fis = {}, flow.instruments
  for i, s in ipairs(flow.voiceStreams) do
    local id = fis[i] and fis[i].id or -1
    for line in (dumpOf(s) .. "\n"):gmatch("(.-)\n") do
      local sp = line:match(": kNoteEvent %(id:%d+%).-%s([A-G][#bx]*%-?%d+) %(ends")
        or line:match(": kGraceNoteEvent %(id:%d+%).-,%s*([A-G][#bx]*%-?%d+)%s*$")
      if sp then keys[#keys + 1] = id .. ":" .. sp end
    end
  end
  table.sort(keys)
  return keys
end

local function flowSummary(app)
  local out = {}
  for _, f in ipairs(app.currentScore.flows) do
    out[#out + 1] = f.id .. "=" .. #noteKeys(f) .. "n/" .. #f.players .. "p"
  end
  return table.concat(out, ",")
end

probe.run("23_paste_undo", function(p)
  local app = DoApp.DoApp()
  local ctx = DoCore.PropertyContext()
  local music = app.currentScore.flows[p.args.flowIndex or 1]
  local musicId = music.id
  local want = noteKeys(music)
  local summaryBefore = flowSummary(app)
  p:fact("summaryBefore", summaryBefore)

  -- scratch flow with exactly the music flow's players
  local before = {}
  for _, f in ipairs(app.currentScore.flows) do before[f.id] = true end
  app:doCommand("Project.Flow.New")
  local scratchId
  for _, f in ipairs(app.currentScore.flows) do if not before[f.id] then scratchId = f.id end end
  if not p:check("new flow", scratchId ~= nil) then return end
  local member = {}
  for _, pl in ipairs(music.players) do member[pl.instruments[1].id] = true end
  local scratch = flowById(app, scratchId)
  for _, pl in ipairs(scratch.players) do
    if not member[pl.instruments[1].id] then scratch:removePlayer(pl) end
  end

  -- copy the music flow's notes on every staff
  local t0 = os.clock()
  app:doCommand("Edit.SelectNone")
  music = flowById(app, musicId)
  local topD = dumpOf(music.voiceStreams[1])
  local firstId = tonumber(topD:match(": k%a+ %(id:(%d+)%)"))
  app:doCommand("EventEdit.Select?FlowID=" .. musicId .. "&EventID=" .. firstId .. "&EventBlockID=" .. blockId(topD))
  local strategy = p.args.strategy or "bottom"
  p:fact("firstEventLine", topD:match("[^\n]*%(id:" .. firstId .. "%)[^\n]*") or "?")
  p:fact("staves", #music.staveStreams)
  if strategy == "bottom" then
    app:doCommand("EventEdit.NavigateDownExtendBottom")
  elseif strategy == "steps" then
    for _ = 2, #music.staveStreams do app:doCommand("EventEdit.NavigateDownExtend") end
  elseif strategy == "steps-after" then
    app:doCommand("Edit.SelectToStartOfFlow")
    app:doCommand("Edit.SelectAtEndOfFlow")
    for _ = 2, #music.staveStreams do app:doCommand("EventEdit.NavigateDownExtend") end
  end
  app:doCommand("Edit.SelectToStartOfFlow")
  app:doCommand("Edit.SelectAtEndOfFlow")
  app:doCommand("Filter.NotesAndChords")
  app:doCommand("Edit.Copy")

  -- paste onto a temporary note at the start of the scratch flow's top staff
  scratch = flowById(app, scratchId)
  local top = scratch.voiceStreams[1]
  local temp = top:createNote(RL(0), RL(1), DoCore.MIDIPitchWithSpelling.fromString("C5"))
  app:doCommand("Edit.SelectNone")
  app:doCommand("EventEdit.Select?FlowID=" .. scratchId .. "&EventID=" .. temp.id .. "&EventBlockID=" .. blockId(dumpOf(top)))
  app:doCommand("Edit.Paste")
  app:doCommand("Edit.SelectNone")
  p:fact("secondsToCopyAndPaste", os.clock() - t0)

  -- read it
  scratch = flowById(app, scratchId)
  local got = noteKeys(scratch)
  local heads, unreadable = {}, 0
  for _, s in ipairs(scratch.voiceStreams) do
    local ok, list = pcall(function() return s.events end)
    if not ok then unreadable = unreadable + 1 else
      for _, e in ipairs(list) do
        local okT, t = pcall(tostring, e)
        if okT and (t:find("kNoteEvent", 1, true) or t:find("kGraceNoteEvent", 1, true)) then
          local h = tostring(e.propertyTable:get("kNoteheadSetOverride", ctx)) .. "|" .. tostring(e.propertyTable:get("kEventColour", ctx))
          heads[h] = (heads[h] or 0) + 1
        end
      end
    end
  end
  p:fact("headsAndColours", heads)
  local per = {}
  for _, st in ipairs(scratch.voiceStreams) do
    local n = 0
    for _ in dumpOf(st):gmatch(": k%a*NoteEvent %(id:") do n = n + 1 end
    per[#per + 1] = st.id .. ":" .. n
  end
  p:fact("scratchStreamNotes", table.concat(per, " "))
  local mper = {}
  for _, st in ipairs(flowById(app, musicId).voiceStreams) do
    local n = 0
    for _ in dumpOf(st):gmatch(": k%a*NoteEvent %(id:") do n = n + 1 end
    mper[#mper + 1] = st.id .. ":" .. n
  end
  p:fact("musicStreamNotes", table.concat(mper, " "))
  p:check("every pasted stream is readable", unreadable == 0, unreadable)
  p:check("pasted notes match the source exactly (instrument and spelling)", table.concat(got, " ") == table.concat(want, " "),
    #got .. " vs " .. #want)
  if table.concat(got, " ") ~= table.concat(want, " ") then
    local count = {}
    for _, k in ipairs(want) do count[k] = (count[k] or 0) + 1 end
    for _, k in ipairs(got) do count[k] = (count[k] or 0) - 1 end
    local missing, extra = {}, {}
    for k, n in pairs(count) do
      if n > 0 then missing[#missing + 1] = k .. "x" .. n elseif n < 0 then extra[#extra + 1] = k .. "x" .. -n end
    end
    table.sort(missing)
    table.sort(extra)
    p:fact("missing", table.concat(missing, " "))
    p:fact("extra", table.concat(extra, " "))
    -- the source lines of the missing spellings, to see what kind of notes they are
    local lines = {}
    local mfl = flowById(app, musicId)
    for _, st in ipairs(mfl.voiceStreams) do
      for line in (dumpOf(st) .. "\n"):gmatch("(.-)\n") do
        for _, k in ipairs(missing) do
          local sp = k:match(":(.-)x%d+$")
          if #lines < 30 and line:find("Event %(id:%d+%)") and line:find(" " .. sp:gsub("%-", "%%-") .. "[ ,]") then
            lines[#lines + 1] = st.id .. ": " .. line:sub(1, 160)
          end
        end
      end
    end
    p:fact("missingLines", lines)
    -- by position: "<spelling>@<pos>" keys of every note, source and pasted
    local function posKeys(flow, skipId)
      local keys, lineOf = {}, {}
      for _, st in ipairs(flow.voiceStreams) do
        for line in (dumpOf(st) .. "\n"):gmatch("(.-)\n") do
          local id = tonumber(line:match(": k%a*NoteEvent %(id:(%d+)%)"))
          if id and id ~= skipId then
            local pos = line:match(" at ([^,]+),") or line:match(" at (%S+)")
            local sp = line:match("%s([A-G][#bx]*%-?%d+) %(ends") or line:match(",%s*([A-G][#bx]*%-?%d+)%s*$") or "?"
            local k = sp .. "@" .. tostring(pos)
            keys[k] = (keys[k] or 0) + 1
            lineOf[k] = st.id .. ": " .. line:sub(1, 170)
          end
        end
      end
      return keys, lineOf
    end
    local src, srcLine = posKeys(flowById(app, musicId))
    local dst = posKeys(flowById(app, scratchId), temp.id)
    local gone = {}
    for k, n in pairs(src) do
      if (dst[k] or 0) < n then gone[#gone + 1] = srcLine[k] .. "  [x" .. (n - (dst[k] or 0)) .. "]" end
    end
    table.sort(gone)
    p:fact("missingByPosition", gone)
  end

  -- undo the paste, then the new flow
  app:doCommand("Edit.Undo")
  local afterOne = flowById(app, scratchId)
  p:fact("afterFirstUndo", afterOne and (#noteKeys(afterOne) .. " notes left in the scratch flow") or "scratch flow gone")
  app:doCommand("Edit.Undo")
  p:check("scratch flow gone after two undos", flowById(app, scratchId) == nil)
  local summaryAfter = flowSummary(app)
  p:fact("summaryAfter", summaryAfter)
  p:check("every flow as it was", summaryAfter == summaryBefore, summaryAfter)
end)
