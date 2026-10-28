-- Draws a chart into its own first flow (docs/dorico-lua-guide.md, section 5): chart players that only the chart
-- flow holds, one system per section (a hidden open-meter time signature and a system break at each section after
-- the first), stemless notes in the section's notehead set and colour, no naturals, rests, staff labels, barlines
-- or flow headings, and a hidden marker written before anything else.
local chartlayout = require("hbuc.chartlayout")
local commands = require("hbuc.commands")
local constants = require("hbuc.constants")
local eventtext = require("hbuc.eventtext")
local marker = require("hbuc.marker")
local textexport = require("hbuc.textexport")
local doc = require("hbuc.dorico.doc")

local writechart = {}

local function RL(n) return DoCore.RhythmicLength(n) end

local function newFlow(app, log)
  local before = {}
  for _, f in ipairs(app.currentScore.flows) do before[f.id] = true end
  doc.command(app, log, "Project.Flow.New")
  local id
  for _, f in ipairs(app.currentScore.flows) do
    if not before[f.id] then id = f.id end
  end
  if not id then error("Project.Flow.New did not add a flow") end
  doc.command(app, log, commands.renameFlow(id, constants.CHART_FLOW_NAME))
  doc.command(app, log, commands.moveFlowToStart(id))
  if app.currentScore.flows[1].id ~= id then error("the chart flow could not be moved to the start") end
  local flow = doc.flowById(app.currentScore, id)
  for _, pl in ipairs(flow.players) do flow:removePlayer(pl) end
  if #doc.flowById(app.currentScore, id).players ~= 0 then error("the chart flow still holds music players") end
  return id
end

-- Layout options as they were, which Lua cannot read: compare text exports under each candidate
-- (docs/dorico-lua-guide.md, section 4). Both need two or more flows, so they run once the chart flow exists, and
-- each leaves its option as it found it. original: the text export before either is tried.
local function setOption(app, log, fullId, key, value)
  doc.command(app, log, commands.layoutOptions(app.currentScore.openScoreID, fullId, { [key] = value }))
end

local function originalHeadings(app, log, temp, fullId, original)
  setOption(app, log, fullId, "flowHeadingBehaviour", "kNoFlowHeadings")
  local none = doc.exportText(app, log, temp, "headings-none")
  setOption(app, log, fullId, "flowHeadingBehaviour", "kAddHeadingsAfterFirstFlow")
  local afterFirst = doc.exportText(app, log, temp, "headings-afterfirst")
  local value = textexport.decideHeadings(original, none, afterFirst)
  setOption(app, log, fullId, "flowHeadingBehaviour", value)
  return value
end

-- A text at the start of the first music flow, so the text export has a row whose page shows where the music
-- starts. Without one, a project with a chart drawn exported the same rows under both flow-break values (the
-- fixture did). Runs fn with it in place and deletes it again whatever happens.
local function withPageProbe(app, chartId, fn)
  local stream
  for _, f in ipairs(app.currentScore.flows) do
    if not stream and f.id ~= chartId and #f.voiceStreams > 0 then stream = f.voiceStreams[1] end
  end
  if not stream then return fn() end
  local probe = stream:createText(RL(0), RL(1), constants.PAGE_PROBE)
  local results = { pcall(fn) }
  stream:delete(probe)
  if not results[1] then error(results[2], 0) end
  return unpack(results, 2)
end

local function originalFlowBreaks(app, log, temp, fullId, original)
  setOption(app, log, fullId, "flowBreakBehaviour", "kNoFlowBreaks")
  local noBreaks = doc.exportText(app, log, temp, "breaks-none")
  setOption(app, log, fullId, "flowBreakBehaviour", "kStartNewPageForFlows")
  local newPage = doc.exportText(app, log, temp, "breaks-newpage")
  local value = textexport.decideFlowBreaks(original, noBreaks, newPage)
  setOption(app, log, fullId, "flowBreakBehaviour", value)
  return value
end

local function inFlow(flow, key)
  for _, k in ipairs(doc.flowKeys(flow)) do
    if k == key then return true end
  end
  return false
end

-- A new chart player, in the chart flow only. Its player id is found later, with every other player's.
local function addPlayer(app, chartId, role)
  local entity = role == "treble" and constants.TREBLE_INSTRUMENT or constants.GRAND_INSTRUMENT
  local key = doc.playerKey(app.currentScore:addPlayer(entity, false, 1))
  for _, f in ipairs(app.currentScore.flows) do
    local has = inFlow(f, key)
    if f.id == chartId and not has then f:addPlayer(doc.playerByKey(app.currentScore, key)) end
    if f.id ~= chartId and has then f:removePlayer(doc.playerByKey(app.currentScore, key)) end
  end
  return key
end

local function idList(ids, keys)
  local out = {}
  for _, k in ipairs(keys) do
    if ids[k] == nil then error("no player id for player " .. tostring(k)) end
    out[#out + 1] = ids[k]
  end
  return table.concat(out, ",")
end

-- The chart flow's voice streams by chart player, in order (a grand staff's treble voice first).
local function streamsByKey(app, chartId)
  local by = {}
  for _, o in ipairs(doc.voiceOwners(doc.flowById(app.currentScore, chartId))) do
    by[o.key] = by[o.key] or {}
    table.insert(by[o.key], o.stream)
  end
  return by
end

local function hasNotes(columns)
  for _, spellings in ipairs(columns) do
    if #spellings > 0 then return true end
  end
  return false
end

local function clearFlow(app, chartId, length)
  for _, s in ipairs(doc.flowById(app.currentScore, chartId).allStreams) do
    s:deleteEventsInRange(RL(0), RL(length + 16))
  end
end

-- built: chartlayout.build output. opts: {log, tempDir, slots, musicKeys, existing = findchart result or nil,
-- newPage = false to let the music follow the chart on its page}.
-- Returns {flowId, chartKeys}.
function writechart.write(app, built, opts)
  local log, temp = opts.log, opts.tempDir
  local fullId = chartlayout.fullScoreLayout(doc.layouts(app.currentScore), opts.musicKeys)
  if not fullId then error("no layout holds every player, so the full score could not be found") end

  -- the flow, and what to restore when the chart is removed
  local chartId, restore, existingPlayers
  if opts.existing then
    chartId = opts.existing.flowId
    restore = {}
    for k, v in pairs(opts.existing.marker.restore) do restore[k] = v end
    existingPlayers = opts.existing.players
  else
    chartId = newFlow(app, log)
    local headings, breaks = withPageProbe(app, chartId, function()
      local original = doc.exportText(app, log, temp, "layout-original")
      return originalHeadings(app, log, temp, fullId, original), originalFlowBreaks(app, log, temp, fullId, original)
    end)
    restore = {
      flowHeadingBehaviour = headings,
      hideEmptyStavesPolicy = "kNever",
      alwaysVisiblePlayers = "",
      playersToShowPlayerName = "",
      flowBreakBehaviour = breaks,
    }
  end

  -- chart players: reuse by role, add what is missing
  local assigned = chartlayout.assign(opts.slots, existingPlayers)
  local slotKeys, chartKeys = {}, {}
  for i, slot in ipairs(opts.slots) do
    slotKeys[i] = assigned.keys[i] or addPlayer(app, chartId, slot.role)
    chartKeys[#chartKeys + 1] = slotKeys[i]
  end
  for _, k in ipairs(assigned.surplus) do chartKeys[#chartKeys + 1] = k end
  -- Player ids, for the commands and layout options that take them. Chart players are named with a space, which
  -- playersToShowPlayerName then shows as their (empty) staff label.
  local ids = doc.playerIds(app, log)
  for _, k in ipairs(chartKeys) do doc.command(app, log, commands.renamePlayer(ids[k], " ")) end
  for _, id in ipairs(chartlayout.partLayouts(doc.layouts(app.currentScore), chartKeys, fullId)) do
    doc.command(app, log, commands.deleteLayout(id))
  end
  local chartFlow = doc.flowById(app.currentScore, chartId)
  for _, l in ipairs(app.currentScore.layouts) do
    if l.id ~= fullId then pcall(function() l:removeFlow(chartFlow) end) end
  end

  -- Memberships Dorico adds by itself (a new player joins every flow; a new flow holds every player), which
  -- chartcheck tolerated because they hold no music: out again.
  if opts.existing then
    for _, k in ipairs(opts.existing.extras or {}) do
      local pl = doc.playerByKey(app.currentScore, k)
      if pl then doc.flowById(app.currentScore, chartId):removePlayer(pl) end
    end
    for _, stray in ipairs(opts.existing.strays or {}) do
      local pl, f = doc.playerByKey(app.currentScore, stray.key), doc.flowById(app.currentScore, stray.flowId)
      if pl and f then f:removePlayer(pl) end
    end
  end

  -- the old chart goes only now, just before its new marker, so a failure above leaves a chart that can be found
  if opts.existing then
    local columns = 0
    for _, s in ipairs(opts.existing.marker.sections) do columns = columns + s.columns end
    clearFlow(app, chartId, columns)
    -- A version 1 marker's chart never changed the flow breaks, so they are still the project's own. They are read
    -- with the chart flow empty again, as for a new chart: a drawn chart can fill page 1, and then both values put
    -- the music on page 2.
    if not restore.flowBreakBehaviour then
      restore.flowBreakBehaviour = withPageProbe(app, chartId, function()
        return originalFlowBreaks(app, log, temp, fullId, doc.exportText(app, log, temp, "layout-original"))
      end)
    end
  end

  -- the marker first, so the chart can always be found again
  local streams = streamsByKey(app, chartId)
  local text = marker.encode({
    chartPlayers = chartKeys, sections = chartlayout.markerSections(built, slotKeys), restore = restore,
  })
  local markerEvent = streams[slotKeys[1]][1]:createText(RL(0), RL(1), text)
  doc.setTrue(markerEvent, "kTextHide")

  -- the sections
  local naturals, firstNotes, voices = {}, {}, {}
  for i, s in ipairs(built.sections) do
    local own = streams[slotKeys[s.slot]]
    local treble, bass = own[1], own[2]
    local function note(stream, pos, spelling)
      local e = stream:createNote(RL(pos), RL(1), DoCore.MIDIPitchWithSpelling.fromString(spelling))
      doc.setTrue(e, "kNoteHideStem")
      if s.noteheadSet then doc.setString(e, "kNoteheadSetOverride", s.noteheadSet) end
      if s.colour ~= "" then doc.setString(e, "kEventColour", s.colour) end
      if spelling:match("^[A-G]%-?%d+$") then naturals[#naturals + 1] = { stream = stream, id = e.id } end
      voices[stream.id] = voices[stream.id] or { stream = stream, first = e.id, pos = pos }
      if pos < voices[stream.id].pos then voices[stream.id].first, voices[stream.id].pos = e.id, pos end
      return e
    end
    local function filler(stream, spelling)
      local e = stream:createNote(RL(s.start), RL(1), DoCore.MIDIPitchWithSpelling.fromString(spelling))
      for _, prop in ipairs({ "kNoteHideNotehead", "kNoteHideStem", "kNoteLedgerLineHide" }) do doc.setTrue(e, prop) end
      voices[stream.id] = voices[stream.id] or { stream = stream, first = e.id, pos = s.start }
      return e
    end
    for c, spellings in ipairs(s.treble) do
      for _, sp in ipairs(spellings) do
        local e = note(treble, s.start + c - 1, sp)
        if not firstNotes[i] and c == 1 then firstNotes[i] = { stream = treble, id = e.id } end
      end
    end
    if bass then
      for c, spellings in ipairs(s.bass) do
        for _, sp in ipairs(spellings) do
          local e = note(bass, s.start + c - 1, sp)
          if not firstNotes[i] and c == 1 then firstNotes[i] = { stream = bass, id = e.id } end
        end
      end
      if not hasNotes(s.treble) then
        local e = filler(treble, "B5")
        firstNotes[i] = firstNotes[i] or { stream = treble, id = e.id }
      end
      if not hasNotes(s.bass) then
        local e = filler(bass, "D4")
        firstNotes[i] = firstNotes[i] or { stream = bass, id = e.id }
      end
    end
    treble:createText(RL(s.start), RL(1), s.label)
  end

  -- Dumped afresh for each select: the commands between them (a time signature, a system break) may change how a
  -- chart stream is split into blocks, and chart streams are small.
  local function blockOf(stream, eventId)
    return doc.blockIdOf(stream, eventId)
  end

  -- naturals: hidden one at a time with Dorico's own command (a direct property set doesn't take)
  for _, n in ipairs(naturals) do
    doc.select(app, log, chartId, n.id, blockOf(n.stream, n.id))
    doc.command(app, log, "Edit.HideAccidental")
  end

  -- each section after the first: its own bar (hidden open meter, no bar number) on a new system
  for i = 2, #built.sections do
    local first, at = firstNotes[i], built.sections[i].start
    if not first then error("section " .. i .. " has no note to start its system at") end
    doc.select(app, log, chartId, first.id, blockOf(first.stream, first.id))
    doc.command(app, log, commands.timeSignature("X"))
    local division
    for _, e in ipairs(doc.flowById(app.currentScore, chartId).timebaseStreams[1].events) do
      local ev = eventtext.parse(tostring(e))
      if ev.kind == "bardivision" and ev.pos == at then division = e end
    end
    if not division then error("no time signature could be made at section " .. i) end
    doc.setTrue(division, "kTimeSignatureHide")
    doc.setTrue(division, "kBarNumberHide")
    doc.select(app, log, chartId, first.id, blockOf(first.stream, first.id))
    doc.command(app, log, "Edit.CreateSystemBreak")
  end

  -- no rests in any chart voice that holds notes
  for _, v in pairs(voices) do
    doc.select(app, log, chartId, v.first, blockOf(v.stream, v.first))
    doc.command(app, log, "Edit.SelectToStartOfFlow")
    doc.command(app, log, "Edit.SelectAtEndOfFlow")
    doc.command(app, log, "Edit.RemoveRests")
  end
  -- An update can leave an explicit bar rest behind in a cleared bar, which the pass above misses; removed with
  -- the same command on the rest itself (spike/28_bar_rest.lua).
  for _, s in ipairs(doc.flowById(app.currentScore, chartId).voiceStreams) do
    local d = doc.dumpOf(s)
    for _, ev in ipairs(d.events) do
      if ev.kind == "rest" and ev.id then
        doc.select(app, log, chartId, ev.id, doc.blockIdOf(s, ev.id, d))
        doc.command(app, log, "Edit.RemoveRests")
      end
    end
  end
  doc.command(app, log, "Edit.SelectNone")

  -- full-score and chart-flow options
  local openScoreID = app.currentScore.openScoreID
  doc.command(app, log, commands.layoutOptions(openScoreID, fullId, {
    flowHeadingBehaviour = chartlayout.chartHeadings(restore.flowHeadingBehaviour, #app.currentScore.flows - 1),
    hideEmptyStavesPolicy = "kAllSystems",
    alwaysVisiblePlayers = idList(ids, opts.musicKeys),
    ["staffLabelLayoutOptions.playersToShowPlayerName"] = idList(ids, chartKeys),
    flowBreakBehaviour = chartlayout.flowBreaks(opts.newPage ~= false),
  }))
  doc.command(app, log, commands.flowNotationOptions(openScoreID, chartId, {
    ["barlineOptions.finalBarlineType"] = "kNone",
    ["barlineOptions.defaultBarlineType"] = "kNone",
  }))
  return { flowId = chartId, chartKeys = chartKeys, slotKeys = slotKeys, musicIds = idList(ids, opts.musicKeys),
    chartIds = idList(ids, chartKeys) }
end

return writechart
