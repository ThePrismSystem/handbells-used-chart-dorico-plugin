-- The whole chart recipe (docs/dorico-lua-guide.md, section 5), end to end, with a check for
-- every call: a two-section chart (handbells grand staff, then SMBs on a single staff) in its own
-- first flow. Run on a fixture copy by spike/run_recipe.py, which also checks the layout and
-- notation options through the Remote API and captures the page.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua;" .. here .. "../spike/lib/?.lua"
for name in pairs(package.loaded) do -- Dorico keeps one Lua state between runs: reload our modules
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")
local chartflow = require("chartflow")
local layoutopts = require("layoutopts")
local headings = require("headings")
local streammap = require("streammap")
local events = require("events")

local RL = function(n) return DoCore.RhythmicLength(n) end
local TRUE = function() return DoCore.Variant.createString("true") end

local function flowById(score, id)
  for _, f in ipairs(score.flows) do if f.id == id then return f end end
end

local function playerByKey(score, key)
  for _, pl in ipairs(score.players) do if chartflow.playerKey(pl) == key then return pl end end
end

local function blockId(stream)
  return tonumber(stream:dump():match("Start block id: (%d+)")) - 1000
end

local function select(app, flow, stream, event)
  app:doCommand("Edit.SelectNone")
  app:doCommand("EventEdit.Select?FlowID=" .. flow.id .. "&EventID=" .. event.id .. "&EventBlockID=" .. blockId(stream))
end

local function timebaseEventAt(flow, kind, pos)
  for _, e in ipairs(flow.timebaseStreams[1].events) do
    local t = tostring(e)
    if t:find(kind, 1, true) and events.parse(t).pos == pos then return e end
  end
end

local function musicSnapshot(flow)
  local n = 0
  for _, s in ipairs(flow.allStreams) do n = n + #s.events end
  local bars = 0
  for _, e in ipairs(flow.timebaseStreams[1].events) do
    if tostring(e):find("kBarDivisionEvent", 1, true) then bars = bars + 1 end
  end
  return { events = n, bars = bars, players = #flow.players }
end

probe.run("11_chart_recipe", function(p)
  local app = DoApp.DoApp()
  local score = app.currentScore
  local ctx = DoCore.PropertyContext()
  local musicId = score.flows[1].id
  local musicBefore = musicSnapshot(score.flows[1])

  -- flow ---------------------------------------------------------------------------------
  local chart = chartflow.create(app, "Handbells Used Chart")
  p:check("chart flow is first", app.currentScore.flows[1].id == chart.id)
  p:fact("chartFlowId", chart.id)

  -- flow headings: detection works for each value once two flows exist --------------------
  local original = headings.detect(app, score, 0)
  p:fact("originalFlowHeadingBehaviour", original)
  p:check("fixture's heading setting detected", original == "kAlwaysInsertHeadings", original)
  for _, value in ipairs({ "kAddHeadingsAfterFirstFlow", "kNoFlowHeadings", "kAlwaysInsertHeadings" }) do
    app:doCommand(layoutopts.setCommand(score.openScoreID, 0, { flowHeadingBehaviour = value }))
    local seen = headings.detect(app, score, 0)
    p:check("detects " .. value, seen == value, seen)
  end

  -- chart players and their ids ------------------------------------------------------------
  local bells = chartflow.addChartPlayer(app, chart, "instrument.pitchedpercussion.handbells")
  local smb = chartflow.addChartPlayer(app, chart, "instrument.pitchedpercussion.glockenspiel")
  local chartKeys = { chartflow.playerKey(bells), chartflow.playerKey(smb) }
  for _, key in ipairs(chartKeys) do
    local token = "HBUCID" .. key
    app:doCommand("Project.Player.Rename?PlayerID=" .. key .. "&Name=" .. token .. "&ShortName=" .. token)
    p:check("player id " .. key .. " equals its instrument id", tostring(playerByKey(app.currentScore, key)) == token,
      tostring(playerByKey(app.currentScore, key)))
    app:doCommand("Project.Player.Rename?PlayerID=" .. key .. "&Name= &ShortName= ")
    p:check("chart player " .. key .. " renamed to a space", tostring(playerByKey(app.currentScore, key)) == " ")
  end
  local musicKeys = {}
  for _, pl in ipairs(app.currentScore.players) do
    local key = chartflow.playerKey(pl)
    if key ~= chartKeys[1] and key ~= chartKeys[2] then musicKeys[#musicKeys + 1] = key end
  end
  p:fact("chartPlayerIds", table.concat(chartKeys, ","))
  p:fact("musicPlayerIds", table.concat(musicKeys, ","))

  -- full-score layout options (run_recipe.py reads them back) and per-flow notation options --
  app:doCommand(layoutopts.setCommand(score.openScoreID, 0, {
    flowHeadingBehaviour = "kNoFlowHeadings",
    hideEmptyStavesPolicy = "kAllSystems",
    alwaysVisiblePlayers = table.concat(musicKeys, ","),
    ["staffLabelLayoutOptions.playersToShowPlayerName"] = table.concat(chartKeys, ","),
  }))
  app:doCommand(layoutopts.flowNotationCommand(score.openScoreID, chart.id, {
    ["barlineOptions.finalBarlineType"] = "kNone",
    ["barlineOptions.defaultBarlineType"] = "kNone",
  }))

  -- keep the chart out of part layouts ------------------------------------------------------
  local partFlows = {}
  for _, l in ipairs(app.currentScore.layouts) do
    if l.id ~= 0 then
      l:removeFlow(chart)
      partFlows[#partFlows + 1] = tostring(l)
    end
  end
  local allParts = true
  for _, t in ipairs(partFlows) do if not t:find(" 1 flows", 1, true) then allParts = false end end
  p:check("chart flow removed from every part layout", allParts, table.concat(partFlows, "; "))

  -- section 1: handbells -------------------------------------------------------------------
  chart = flowById(app.currentScore, chart.id)
  local v = chart.voiceStreams
  p:check("three chart voice streams (grand staff + single staff)", #v == 3, #v)
  local treble, bass, glock = v[1], v[2], v[3]
  local function note(voice, pos, sounding)
    local e = voice:createNote(RL(pos), RL(1), DoCore.MIDIPitchWithSpelling.fromString(sounding))
    e.propertyTable:set("kNoteHideStem", TRUE(), ctx)
    return e
  end
  local written = { { 0, "C5" }, { 1, "Ab5" }, { 2, "G#5" }, { 3, "G5" }, { 4, "E6" }, { 4, "G#6" } }
  local made = {}
  for _, w in ipairs(written) do made[#made + 1] = note(treble, w[1], w[2]) end
  treble:createText(RL(0), RL(1), "Handbells Used: 5")
  local marker = treble:createText(RL(0), RL(1), "HBUC|1|recipe")
  marker.propertyTable:set("kTextHide", TRUE(), ctx)
  p:check("marker hidden with kTextHide", tostring(marker.propertyTable:get("kTextHide", ctx)) == "true")
  local filler = bass:createNote(RL(0), RL(1), DoCore.MIDIPitchWithSpelling.fromString("D4"))
  for _, prop in ipairs({ "kNoteHideNotehead", "kNoteHideStem", "kNoteLedgerLineHide" }) do
    p:check("invisible bass note: " .. prop, filler.propertyTable:set(prop, TRUE(), ctx))
  end
  local spellings = {}
  for _, e in ipairs(treble.events) do
    local ev = events.parse(tostring(e))
    if ev.kind == "note" then spellings[#spellings + 1] = ev.spelling end
  end
  p:check("treble spellings read back exactly", table.concat(spellings, ",") == "C5,Ab5,G#5,G5,E6,G#6",
    table.concat(spellings, ","))
  p:check("stems hidden", tostring(made[1].propertyTable:get("kNoteHideStem", ctx)) == "true")

  -- the natural on G (after G#) is hidden through Dorico's own command ----------------------
  select(app, chart, treble, made[4])
  app:doCommand("Edit.HideAccidental")
  local natural
  for _, e in ipairs(flowById(app.currentScore, chart.id).voiceStreams[1].events) do
    if e.id == made[4].id then natural = e end
  end
  local hasV3 = false
  for _, n in ipairs(natural.propertyTable:getPropertyNames()) do
    if n == "kNoteAccidentalVisibility_v3" then hasV3 = true end
  end
  p:check("Edit.HideAccidental set kNoteAccidentalVisibility_v3", hasV3)

  -- section 2: SMBs on the Glockenspiel (sounds two octaves up) ------------------------------
  local smbNotes = {}
  for i, s in ipairs({ "C7", "D7", "F#7", "G7" }) do smbNotes[i] = note(glock, 4 + i, s) end
  glock:createText(RL(5), RL(1), "SMBs Used: 4")

  -- section boundary: hidden open-meter time signature, then a system break ------------------
  select(app, chart, glock, smbNotes[1])
  app:doCommand("NoteInput.CreateTimeSignature?Definition=X")
  chart = flowById(app.currentScore, chart.id)
  local tsig = timebaseEventAt(chart, "kBarDivisionEvent", 5)
  if p:check("open-meter time signature at the section start", tsig ~= nil) then
    tsig.propertyTable:set("kTimeSignatureHide", TRUE(), ctx)
    p:check("time signature hidden", tostring(tsig.propertyTable:get("kTimeSignatureHide", ctx)) == "true")
    local okB = pcall(function() return tsig.propertyTable:set("kBarNumberHide", TRUE(), ctx) end)
    p:fact("kBarNumberHideOnBarDivision", okB and tostring(tsig.propertyTable:get("kBarNumberHide", ctx)) or "rejected")
  end
  select(app, chart, glock, smbNotes[1])
  app:doCommand("Edit.CreateSystemBreak")
  chart = flowById(app.currentScore, chart.id)
  p:check("system break at the section start", timebaseEventAt(chart, "kBreakEvent", 5) ~= nil)

  -- implicit rests off in every chart voice --------------------------------------------------
  for _, s in ipairs(chart.voiceStreams) do
    local first
    for _, e in ipairs(s.events) do
      if events.parse(tostring(e)).kind == "note" then first = first or e end
    end
    if first then
      select(app, chart, s, first)
      app:doCommand("Edit.SelectToStartOfFlow")
      app:doCommand("Edit.SelectAtEndOfFlow")
      app:doCommand("Edit.RemoveRests")
    end
  end
  app:doCommand("Edit.SelectNone")

  -- the music is untouched; nothing is left behind ------------------------------------------
  local musicAfter = musicSnapshot(flowById(app.currentScore, musicId))
  p:check("music flow keeps its bars", musicAfter.bars == musicBefore.bars, musicAfter.bars .. " vs " .. musicBefore.bars)
  p:check("music flow keeps its events", musicAfter.events == musicBefore.events,
    musicAfter.events .. " vs " .. musicBefore.events)
  p:check("music flow keeps its players", musicAfter.players == musicBefore.players, musicAfter.players)
  p:check("no stream-map markers left", streammap.leftoverMarkers(flowById(app.currentScore, chart.id)) == 0)
end)
