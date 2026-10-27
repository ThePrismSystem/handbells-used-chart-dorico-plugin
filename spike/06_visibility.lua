-- Two chart sections, one system each, each system showing only its own chart player.
-- args.approach: "inspect" (build + break, report the break event) | "hideEmpty" (also set the layout options)
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua;" .. here .. "../spike/lib/?.lua"
for name in pairs(package.loaded) do -- Dorico keeps one Lua state between runs: reload our modules
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")
local chartflow = require("chartflow")
local layoutopts = require("layoutopts")

local RL = function(n, d) if d then return DoCore.RhythmicLength(n, d) end return DoCore.RhythmicLength(n) end

local function flowById(score, id)
  for _, f in ipairs(score.flows) do if f.id == id then return f end end
end

local function removeRests(app, flow, voice)
  local block = tonumber(voice:dump():match("Start block id: (%d+)")) - 1000
  app:doCommand("Edit.SelectNone")
  app:doCommand("EventEdit.Select?FlowID=" .. flow.id .. "&EventID=" .. voice.events[1].id .. "&EventBlockID=" .. block)
  app:doCommand("Edit.SelectToStartOfFlow")
  app:doCommand("Edit.SelectAtEndOfFlow")
  app:doCommand("Edit.RemoveRests")
  app:doCommand("Edit.SelectNone")
end

probe.run("06_visibility", function(p)
  local app = DoApp.DoApp()
  local score = app.currentScore
  local ctx = DoCore.PropertyContext()
  local chart = chartflow.create(app, "Handbells Used Chart")
  local bells = chartflow.addChartPlayer(app, chart, "instrument.pitchedpercussion.handbells")
  local smb = chartflow.addChartPlayer(app, chart, "instrument.pitchedpercussion.glockenspiel")
  chart = flowById(app.currentScore, chart.id)
  p:fact("chartPlayers", { chartflow.playerKey(bells), chartflow.playerKey(smb) })
  local v = chart.voiceStreams
  p:fact("voiceStreams", (function() local t = {} for i, s in ipairs(v) do t[i] = tostring(s) end return t end)())
  -- streams in player order: handbells treble, handbells bass, glockenspiel
  local hbTreble, glock = v[1], v[3]
  for i, s in ipairs({ "C5", "D5", "E5", "F#5" }) do
    hbTreble:createNote(RL(i - 1), RL(1), DoCore.MIDIPitchWithSpelling.fromString(s))
  end
  hbTreble:createText(RL(0), RL(1), "Handbells Used: 4")
  for i, s in ipairs({ "C7", "D7", "E7", "G7" }) do -- glockenspiel sounds two octaves up: written C5..
    glock:createNote(RL(3 + i), RL(1), DoCore.MIDIPitchWithSpelling.fromString(s))
  end
  glock:createText(RL(4), RL(1), "SMBs Used: 4")
  for _, s in ipairs(flowById(app.currentScore, chart.id).voiceStreams) do
    if #s.events > 0 then removeRests(app, chart, s) end
  end
  app:doCommand(layoutopts.flowNotationCommand(score.openScoreID, chart.id, { ["barlineOptions.finalBarlineType"] = "kNone" }))

  local tb = flowById(app.currentScore, chart.id).timebaseStreams[1]
  local okB, brk = pcall(function() return tb:createSystemBreak(0, RL(4)) end)
  p:check("createSystemBreak(layout 0, pos 4)", okB, tostring(brk))
  if okB then
    local names = {}
    for _, n in ipairs(brk.propertyTable:getPropertyNames()) do
      names[#names + 1] = n .. "=" .. tostring(brk.propertyTable:get(n, ctx))
    end
    p:fact("breakProperties", names)
    p:fact("breakIsSystemBreak", tostring(brk.isSystemBreak))
  end

  if p.args.approach == "hideEmpty" then
    local music = {}
    for _, pl in ipairs(app.currentScore.players) do
      local key = chartflow.playerKey(pl)
      if key ~= chartflow.playerKey(bells) and key ~= chartflow.playerKey(smb) then music[#music + 1] = key end
    end
    p:fact("alwaysVisiblePlayers", table.concat(music, ","))
    app:doCommand(layoutopts.setCommand(score.openScoreID, 0, {
      hideEmptyStavesPolicy = "kAllSystems",
      alwaysVisiblePlayers = table.concat(music, ","),
    }))
  end
end)
