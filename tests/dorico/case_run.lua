-- main.run with a scripted dialog on a scratch copy of the fixture: the whole run as a user would make it.
--   args.answer: "draw" (everything selected, combined), "same-head" (chimes set to the handbells' head),
--                "remove" (Remove Existing Chart ticked) or "cancel"
--   args.expect: "drawn", "replaced", "sameHead", "noChart", "notFull", "saveFailed" or "cancelled"
--   args.startMode: a Dorico mode to be in first (kEngraveMode...); args.startLayout: a layout to show first
--   args.blockSave: File.Save does nothing
--   args.choose: the button id to answer any question before the dialog with (by default, its cancel)
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../../"
local mine = here .. "lib/?.lua;" .. repo .. "spike/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
-- first, whatever came before: the plug-in's entry file (test_run.py's RealDialog) leaves its install on the
-- path, and an older install there would be loaded instead
if package.path:sub(1, #mine + 1) ~= mine .. ";" then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("case_run", function(p)
  -- required here, not above: a module that fails to load is then reported, and the copy closed
  local cases = require("cases")
  local chartcase = require("chartcase")
  local constants = require("hbuc.constants")
  local files = require("hbuc.dorico.files")
  local findchart = require("hbuc.dorico.findchart")
  local main = require("hbuc.main")

  local M = constants.MESSAGES

  local answer = p.args.answer
  local ctx = cases.context(p, {
    respond = function(req)
      if answer == "cancel" then return nil end
      local heads = {}
      for k, v in pairs(chartcase.HEADS) do heads[k] = v end
      if answer == "same-head" then heads.chimes = heads.bells end
      local shapes, colours = {}, {}
      for _, k in ipairs(req.kinds) do
        shapes[k.kind] = constants.SHAPE_MATCH
        if k.colourLabel then colours[k.kind] = k.colour or "" end
      end
      local chosen, atPitch = req.selected, {}
      if answer == "organ" or answer == "organ-at-pitch" then chosen = { "Organ" } end
      if answer == "organ-at-pitch" then atPitch = { "Organ" } end
      return { version = req.version, runId = req.runId, cancelled = false, instruments = chosen,
        mode = req.modes[1], heads = heads, shapes = shapes, colours = colours, remove = answer == "remove",
        atPitch = atPitch }
    end,
    choose = p.args.choose and function() return p.args.choose end,
  })
  -- where the user left Dorico: another mode, or a part on screen
  if p.args.startMode then
    ctx.app:doCommand(require("hbuc.commands").setMode(p.args.startMode))
  end
  if p.args.startLayout then
    ctx.app:doCommand("Window.SwitchToLayout?OpenScoreID=" .. ctx.app.currentScore.openScoreID
      .. "&ScoreLayoutViewContainerID=0&LayoutID=" .. p.args.startLayout)
    p:fact("switched", ctx.app.currentLayoutID == p.args.startLayout)
    if ctx.app.currentLayoutID ~= p.args.startLayout then
      p:fact("skip", "could not show a part from Lua")
      return
    end
  end
  -- a save that does not happen (a locked file, say): File.Save is swallowed
  if p.args.blockSave then
    local real = ctx.app
    ctx.app = setmetatable({}, { __index = function(_, k)
      if k == "doCommand" then
        return function(_, command)
          if command == "File.Save" then return end
          return real:doCommand(command)
        end
      end
      -- luabind refuses a method called on the proxy (app:save, for one): call it on the app itself
      local v = real[k]
      if type(v) == "function" then return function(_, ...) return v(real, ...) end end
      return v
    end })
  end
  local settingsPath = ctx.folders.data .. "settings.json"
  if p.args.freshSettings then os.remove(settingsPath) end
  local project = cases.runFolder() .. "scratch.dorico"
  local savedBefore = files.modified(project)
  local summaryBefore = cases.summary(ctx.app.currentScore)

  local out = main.run(ctx)
  local text = (p.facts.shown[1] or {}).text or ""
  p:fact("outcome", out)
  p:fact("text", text)
  local saved = files.modified(project) ~= savedBefore
  local found = findchart.find(ctx.app, ctx.log, ctx.folders.temp)
  local function has(s) return text:find(s, 1, true) ~= nil end

  local expect = p.args.expect
  if expect == "drawn" or expect == "replaced" then
    p:check("one message", #p.facts.shown == 1, #p.facts.shown)
    p:check("a chart is there", found.status == "ok", found.status)
    for _, label in ipairs({ "Handbells Used: 20", "Handchimes Used: 6", "SMBs Used: 4", "P&F Handbells Used: 2",
      "Whitechapel Handbells Used: 2" }) do
      p:check("reports " .. label, has(label))
    end
    p:check("names the unrecognised notehead", has("1 note(s) with an unrecognised notehead were skipped: X Noteheads"))
    -- the fixture's lowest note is written B1, which is bell B2: inside C2-C9 (the warning is unit-tested)
    p:check("no bell out of range", not has("Bells outside C2-C9"))
    p:check("saved first", saved)
    p:check("remembered the settings", files.read(settingsPath) ~= nil)
    if expect == "replaced" then
      p:check("says it replaced the chart", text:sub(-#M.chartWasReplaced) == M.chartWasReplaced)
    else
      p:check("replaced nothing", not has(M.chartWasReplaced))
    end
  elseif expect == "sameHead" then
    p:check("refused", out.ok == false)
    p:check("explains", text == "More than one instrument is set to the Default Noteheads notehead. "
      .. M.sameNoteheadChosen, text)
    p:check("not saved", not saved)
    p:check("no chart", found.status == "none")
  elseif expect == "noChart" then
    p:check("says there is no chart", text == M.noChartToRemove, text)
    p:check("no chart", found.status == "none")
  elseif expect == "notFull" then
    p:check("asks for the full score", text == M.notFullScore, text)
    p:check("not saved", not saved)
    p:check("no chart", found.status == "none")
  elseif expect == "saveFailed" then
    p:check("says the save failed", text == M.saveFailed, text)
    p:check("no chart", found.status == "none")
  elseif expect == "organ" then
    -- the chart's visible notes (invisible fillers left out), as their spellings
    local eventtext = require("hbuc.eventtext")
    local doc = require("hbuc.dorico.doc")
    local spellings, seen = {}, {}
    if p:check("a chart is there", found.status == "ok", found.status) then
      for _, s in ipairs(doc.flowById(ctx.app.currentScore, found.flowId).voiceStreams) do
        for _, e in ipairs(s.events) do
          local ev = eventtext.parse(tostring(e))
          if ev.kind == "note" and doc.getString(e, "kNoteHideNotehead") ~= "true" and not seen[ev.spelling] then
            seen[ev.spelling] = true
            spellings[#spellings + 1] = ev.spelling
          end
        end
      end
    end
    table.sort(spellings)
    local want = {}
    for _, sp in ipairs(p.args.spellings or {}) do want[#want + 1] = sp end
    table.sort(want)
    p:fact("spellings", spellings)
    p:check("the chart's notes", table.concat(spellings, " ") == table.concat(want, " "), table.concat(spellings, " "))
  elseif expect == "cancelled" then
    p:check("shows nothing", #p.facts.shown == 0, #p.facts.shown)
    p:check("not saved", not saved)
    p:check("music unchanged", cases.summary(ctx.app.currentScore) == summaryBefore)
    p:check("settings not written", files.read(settingsPath) == nil)
    p:check("no chart", found.status == "none")
  end
end)
