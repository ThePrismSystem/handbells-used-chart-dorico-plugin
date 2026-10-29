-- Reads the players and every note of the music, with noteheads and colours, without leaving any change behind.
-- docs/dorico-lua-guide.md, section 3:
--   * stream:dump() lists every note with its sounding spelling, whatever else the stream holds;
--   * flow.instruments says which instrument owns each voice stream;
--   * noteheads and colours need stream.events, which throws on lyrics, slurs, playing techniques and the like.
--     Each such flow's notes are copied (filtered to notes and chords) into a scratch flow of its own and read
--     there, and all the scratch flows are taken away again together, with the run's one Edit.Undo.
local dump = require("hbuc.dump")
local eventtext = require("hbuc.eventtext")
local instruments = require("hbuc.instruments")
local reading = require("hbuc.reading")
local doc = require("hbuc.dorico.doc")

local readscore = {}

-- Event kinds with a Lua class (spike/17_api_map.lua lists the bound classes). Any other kind in a stream makes
-- stream.events throw.
local WRAPPABLE = {
  kNoteEvent = true, kGraceNoteEvent = true, kRestEvent = true, kBarRestEvent = true, kTextEvent = true,
  kTupletEvent = true, kClefEvent = true, kBreakEvent = true, kOttavaLineEvent = true, kBarDivisionEvent = true,
  kTonalityDivisionEvent = true, kDynamicGroupEvent = true,
}

local function lists(e, property)
  for _, name in ipairs(e.propertyTable:getPropertyNames()) do
    if name == property then return true end
  end
  return false
end

-- A property's value, and whether the note has one Lua can't read. A colour or notehead set in Dorico (by command,
-- the Properties panel or the Notations menu) reads back as "", like none at all, but the note still lists the
-- property.
local function valueOf(e, ctx, property)
  local value = tostring(e.propertyTable:get(property, ctx))
  if value ~= "" then return value, false end
  return "", lists(e, property)
end

-- The note and grace note events of a readable list, with notehead set and colour.
local function noteEvents(list)
  local out = {}
  local ctx = DoCore.PropertyContext()
  for _, e in ipairs(list) do
    local ok, text = pcall(tostring, e)
    if ok then
      local ev = eventtext.parse(text)
      if (ev.kind == "note" or ev.kind == "grace") and ev.spelling then
        local colour, colourUnreadable = valueOf(e, ctx, "kEventColour")
        local head, headUnreadable = valueOf(e, ctx, "kNoteheadSetOverride")
        out[#out + 1] = {
          id = ev.id, spelling = ev.spelling, grace = ev.kind == "grace", pos = ev.pos,
          head = head, headUnreadable = headUnreadable,
          colour = colour, colourUnreadable = colourUnreadable,
        }
      end
    end
  end
  return out
end

-- Players in score order, named as the dialog lists them (repeats told apart), and the name of each instrument.
local function namePlayers(score, skipKeys)
  local kept, names = {}, {}
  for _, pl in ipairs(score.players) do
    local key = doc.playerKey(pl)
    if not skipKeys[key] then
      kept[#kept + 1] = { player = pl, key = key }
      names[#names + 1] = tostring(pl)
    end
  end
  local unique = instruments.unique(names)
  local players, nameOf = {}, {}
  for i, e in ipairs(kept) do
    players[i] = { key = e.key, name = unique[i] }
    for _, ins in ipairs(e.player.instruments) do nameOf[ins.id] = unique[i] end
  end
  return players, nameOf
end

-- A fingerprint of the music: each flow's dumped note count and player count, leaving out flow skipId.
function readscore.summary(score, skipId)
  local parts = {}
  for _, f in ipairs(score.flows) do
    if f.id ~= skipId then
      local n = 0
      for _, s in ipairs(f.voiceStreams) do n = n + #dump.notes(doc.dumpOf(s)) end
      parts[#parts + 1] = f.id .. "=" .. n .. "n/" .. #f.players .. "p"
    end
  end
  return table.concat(parts, ",")
end

-- Copies a flow's notes into a new scratch flow holding only its players and reads them there. The scratch flow
-- stays until takeAway; its id goes into scratchIds before anything else, so a failure still takes it away.
local function copyAndRead(app, log, flowId, nameOf, scratchIds)
  local existing = {}
  for _, f in ipairs(app.currentScore.flows) do existing[f.id] = true end
  doc.command(app, log, "Project.Flow.New")
  local scratchId
  for _, f in ipairs(app.currentScore.flows) do
    if not existing[f.id] then scratchId = f.id end
  end
  if not scratchId then error("Project.Flow.New did not add a flow") end
  scratchIds[#scratchIds + 1] = scratchId

  local flow = doc.flowById(app.currentScore, flowId)
  local member = {}
  for _, k in ipairs(doc.flowKeys(flow)) do member[k] = true end
  local scratch = doc.flowById(app.currentScore, scratchId)
  for _, pl in ipairs(scratch.players) do
    if not member[doc.playerKey(pl)] then scratch:removePlayer(pl) end
  end

  -- the music flow's whole range, on every staff, notes and chords only. The range starts on the staff of the first
  -- voice holding a note or rest, which is lower down when the first players have nothing to play: note whose voice
  -- that is, and which of its instrument's voices.
  local first, block, firstKey, nth
  local owners, voices = doc.voiceOwners(flow), {}
  for _, o in ipairs(owners) do voices[o.key] = (voices[o.key] or 0) + 1 end
  local seen = {}
  for _, o in ipairs(owners) do
    seen[o.key] = (seen[o.key] or 0) + 1
    local d = doc.dumpOf(o.stream)
    first = dump.firstEventId(d)
    if first then
      block = doc.blockIdOf(o.stream, first, d)
      firstKey, nth = o.key, seen[o.key]
      break
    end
  end
  if not first then return {} end
  doc.select(app, log, flowId, first, block)
  doc.command(app, log, "Edit.SelectToStartOfFlow")
  doc.command(app, log, "Edit.SelectAtEndOfFlow")
  for _ = 2, #flow.staveStreams do doc.command(app, log, "EventEdit.NavigateDownExtend") end
  doc.command(app, log, "Filter.NotesAndChords")
  doc.command(app, log, "Edit.Copy")

  -- Pasted onto a temporary note at the start of the same staff in the scratch flow, which has one voice per staff.
  -- A grand staff's voices are [treble, bass] in both flows, so the nth voice is on the nth staff when the music
  -- flow also has one voice per staff for that instrument. With more, which staff a voice is on can't be told, and
  -- the instrument's first staff is used.
  scratch = doc.flowById(app.currentScore, scratchId)
  local staves = {}
  for _, o in ipairs(doc.voiceOwners(scratch)) do
    if o.key == firstKey then staves[#staves + 1] = o.stream end
  end
  local top = staves[#staves == voices[firstKey] and nth or 1]
  if not top then error("the scratch flow has no voice for instrument " .. tostring(firstKey)) end
  local temp = top:createNote(DoCore.RhythmicLength(0), DoCore.RhythmicLength(1),
    DoCore.MIDIPitchWithSpelling.fromString("C5"))
  local tempId = temp.id
  doc.select(app, log, scratchId, tempId, doc.blockIdOf(top, tempId))
  doc.command(app, log, "Edit.Paste")

  -- The filter keeps note-attached lines with their notes, and a line has no Lua class: delete every event the
  -- copy holds that is not one Lua can list, one by one, in the scratch flow only.
  scratch = doc.flowById(app.currentScore, scratchId)
  for _, s in ipairs(scratch.voiceStreams) do
    if not pcall(function() return s.events end) then
      local d = doc.dumpOf(s)
      for _, ev in ipairs(d.events) do
        local tag = ev.raw:match("^(k%a+)")
        if ev.id and not WRAPPABLE[tag] then
          doc.select(app, log, scratchId, ev.id, doc.blockIdOf(s, ev.id, d))
          doc.command(app, log, "Edit.Delete")
        end
      end
    end
  end
  doc.command(app, log, "Edit.SelectNone")

  local read = {}
  scratch = doc.flowById(app.currentScore, scratchId)
  for _, o in ipairs(doc.voiceOwners(scratch)) do
    local okE, list = pcall(function() return o.stream.events end)
    if not okE then
      local kinds = {}
      for _, ev in ipairs(doc.dumpOf(o.stream).events) do kinds[#kinds + 1] = ev.raw:match("^(k%a+)") end
      log:line("unreadable copy stream", o.stream.id, table.concat(kinds, " "):sub(1, 2000))
      error("the copy of the music could not be read")
    end
    local name = nameOf[o.key]
    for _, n in ipairs(noteEvents(list)) do
      if n.id ~= tempId and name then
        n.instrument = name
        read[#read + 1] = n
      end
    end
  end
  return read
end

-- Takes every scratch flow away with ONE Edit.Undo, which rolls back everything this run has done, the temporary
-- notes made with createNote included, and nothing done before the run. A second undo in the same run would also
-- take back the user's previous action (spike/29_undo_experiments.py, E9 against E10), so there is never a second
-- one.
local function takeAway(app, log, scratchIds, before)
  doc.command(app, log, "Edit.Undo")
  for _, id in ipairs(scratchIds) do
    if doc.flowById(app.currentScore, id) then
      error({ code = "scratchLeft", flowNumber = doc.flowNumber(app.currentScore, id) })
    end
  end
  local after = readscore.summary(app.currentScore)
  if after ~= before then
    -- which flows differ, for the run log
    local was, now, diff = {}, {}, {}
    for id, part in before:gmatch("(%d+)=([^,]*)") do was[id] = part end
    for id, part in after:gmatch("(%d+)=([^,]*)") do now[id] = part end
    for id, part in pairs(was) do
      if now[id] ~= part then diff[#diff + 1] = "flow " .. id .. ": " .. part .. " -> " .. tostring(now[id]) end
    end
    for id, part in pairs(now) do
      if not was[id] then diff[#diff + 1] = "flow " .. id .. ": new, " .. part end
    end
    log:line("the project changed while it was being read:", table.concat(diff, "; "))
    error("the project changed while it was being read (" .. table.concat(diff, "; ") .. ")")
  end
end

-- opts: {log, skipFlowId, skipKeys = {[key] = true}, forcePaste}. Returns {players = {{key, name}}, records,
-- unread, merged, pastedFlows, dumped, read, flowNumbers}: dumped and read are the notes the records were made from,
-- each with its flowId and position, kept so noteheads Lua couldn't read (headUnreadable) can be taken from a
-- MusicXML export (hbuc.xmlnotes). Call it at most once per run, before the run edits anything: its copies go with
-- the run's one Edit.Undo, which would take back anything else the run had done by then.
function readscore.scan(app, opts)
  local log = opts.log
  local players, nameOf = namePlayers(app.currentScore, opts.skipKeys or {})
  local flowIds = {}
  for _, f in ipairs(app.currentScore.flows) do
    if f.id ~= opts.skipFlowId then flowIds[#flowIds + 1] = f.id end
  end

  local before = readscore.summary(app.currentScore)
  local flowNumbers = {}
  for _, flowId in ipairs(flowIds) do flowNumbers[flowId] = doc.flowNumber(app.currentScore, flowId) end
  local dumped, read, scratchIds = {}, {}, {}
  local ok, err = pcall(function()
    for _, flowId in ipairs(flowIds) do
      local flow = doc.flowById(app.currentScore, flowId)
      local flowDumped, direct, readable = {}, {}, not opts.forcePaste
      for _, o in ipairs(doc.voiceOwners(flow)) do
        local name = nameOf[o.key]
        if name then
          for _, n in ipairs(dump.notes(doc.dumpOf(o.stream))) do
            flowDumped[#flowDumped + 1] = { instrument = name, spelling = n.spelling, grace = n.grace, pos = n.pos,
              flowId = flowId }
          end
          if readable then
            local okE, list = pcall(function() return o.stream.events end)
            if okE then
              for _, n in ipairs(noteEvents(list)) do
                n.instrument = name
                direct[#direct + 1] = n
              end
            else
              readable = false
            end
          end
        end
      end
      -- stream.events can also list fewer notes than a stream holds: trusted only when every count agrees
      if readable and not reading.countsMatch(flowDumped, direct) then readable = false end
      log:line("flow", flowId, #flowDumped, "notes", readable and "read directly" or "read through a copy")
      if #flowDumped > 0 and not readable then direct = copyAndRead(app, log, flowId, nameOf, scratchIds) end
      for _, n in ipairs(flowDumped) do dumped[#dumped + 1] = n end
      for _, n in ipairs(direct) do
        n.flowId = flowId
        read[#read + 1] = n
      end
    end
  end)
  if #scratchIds > 0 then takeAway(app, log, scratchIds, before) end
  if not ok then error(err, 0) end

  local records, unread, merged = reading.records(dumped, read)
  return { players = players, records = records, unread = unread, merged = merged, pastedFlows = #scratchIds,
    dumped = dumped, read = read, flowNumbers = flowNumbers }
end

return readscore
