-- One run of the plug-in, start to finish. Every effect goes through ctx (hbuc.dorico.context): the Dorico app, the
-- dialog, the question windows, the message window, the folders and the log, so tests can run it with a scripted
-- dialog. Nothing in the project changes before the user clicks OK and the project is saved. The read only saves a
-- copy into the temp folder.
local chartlayout = require("hbuc.chartlayout")
local combine = require("hbuc.combine")
local commands = require("hbuc.commands")
local constants = require("hbuc.constants")
local guards = require("hbuc.guards")
local options = require("hbuc.options")
local plan = require("hbuc.plan")
local report = require("hbuc.report")
local request = require("hbuc.request")
local shapes = require("hbuc.shapes")
local textexport = require("hbuc.textexport")
local transpose = require("hbuc.transpose")
local doc = require("hbuc.dorico.doc")
local files = require("hbuc.dorico.files")
local findchart = require("hbuc.dorico.findchart")
local readscore = require("hbuc.dorico.readscore")
local removechart = require("hbuc.dorico.removechart")
local safe = require("hbuc.dorico.safe")
local writechart = require("hbuc.dorico.writechart")

local main = {}

local M = constants.MESSAGES

local function result(ok, kind, text)
  return { ok = ok, kind = kind, text = text or "" }
end

local function failure(err)
  if type(err) == "table" then return tostring(err.message or err.code) end
  return tostring(err)
end

-- Unrecognised noteheads are named by the notehead set's display name, as the dialog lists them.
local function namedWarnings(warnings)
  for _, w in ipairs(warnings) do
    if w.type == "unknown-notehead" and w.names then
      local names = {}
      for i, id in ipairs(w.names) do names[i] = shapes.displayName(id) end
      w.names = names
    end
  end
end

-- The run itself. Returns {ok, kind = "info"|"warning"|"error", text}.
function main.chart(ctx)
  local app, log = ctx.app, ctx.log
  local temp = ctx.folders.temp

  -- 1. guards
  local version = app.versionString
  if not guards.supported(version) then
    return result(false, "error", string.format(M.untestedDorico, tostring(version)))
  end
  local okScore, score = pcall(function() return app.currentScore end)
  if not okScore or not score or #score.players == 0 then return result(false, "error", M.noProject) end
  -- No property gives the project's file; the text export's Path column is empty until it has been saved.
  local projectPath = textexport.projectPath(doc.exportText(app, log, temp, "project"))
  if projectPath == "" then return result(false, "warning", M.notSaved) end

  -- Every selection and note-input step below works in Write mode on the full score, with no note input running.
  doc.command(app, log, "NoteInput.Exit")
  doc.command(app, log, commands.setMode("kWriteMode"))
  local allKeys = {}
  for _, pl in ipairs(app.currentScore.players) do allKeys[#allKeys + 1] = doc.playerKey(pl) end
  local fullId = chartlayout.fullScoreLayout(doc.layouts(app.currentScore), allKeys)
  if fullId == nil or app.currentLayoutID ~= fullId then return result(false, "warning", M.notFullScore) end

  -- 2. an existing chart must be positively identified before anything else
  local found = findchart.find(app, log, temp)
  if found.status == "invalid" then return result(false, "error", string.format(M.chartUnidentified, found.reason)) end
  local chart = found.status == "ok" and found or nil

  -- 3. read the music (not the chart)
  local skipKeys = {}
  if chart then
    for _, k in ipairs(chart.marker.chartPlayers) do skipKeys[k] = true end
  end
  local okRead, scan = safe.call(log, "read", readscore.scan, app,
    { log = log, skipFlowId = chart and chart.flowId, skipKeys = skipKeys, layoutId = fullId, tempDir = temp })
  if not okRead then return result(false, "error", string.format(M.readFailed, failure(scan), log.path)) end

  -- 3b. a rare notehead set beside a common one of the same shape: the user says whether they chart together
  for _, group in ipairs(combine.groups(scan.records)) do
    local answer = ctx.choose(combine.question(group))
    log:line("combine", group.shape, tostring(answer))
    if not answer then return result(false, "error", constants.DIALOG.dialogFailed) end
    if answer == "combine" then combine.apply(scan.records, group) end
  end

  -- 4. the dialog
  local settingsPath = ctx.folders.data .. "settings.json"
  local settings = options.decodeSettings(files.read(settingsPath) or "")
  local names = {}
  for _, pl in ipairs(scan.players) do names[#names + 1] = pl.name end
  -- A fresh id each run: the dialog echoes it, so a response file left over from another run is never read.
  local runId = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
  local req = request.build({ players = names, records = scan.records, settings = settings, chartExists = chart ~= nil,
    runId = runId })
  local okAsk, raw = pcall(ctx.dialog, req)
  if not okAsk then log:line("the dialog failed:", raw) end
  local resp = okAsk and request.parse(raw, req) or nil
  if not resp then
    log:line("cancelled")
    return result(false, "info", "")
  end

  -- 5. choices that cannot work are refused before anything is saved
  if not resp.remove then
    local duplicate = options.duplicateHead(resp.heads)
    if duplicate ~= "" then
      return result(false, "error", "More than one instrument is set to the " .. shapes.displayName(duplicate)
        .. " notehead. " .. M.sameNoteheadChosen)
    end
    if #resp.instruments == 0 then return result(false, "error", M.noInstrumentSelected) end
  end

  -- 6. remember the choices, and save: File > Revert then takes the whole run back
  files.write(settingsPath, options.encodeSettings(request.settingsAfter(settings, req, resp)))
  -- File > Revert is the run's undo, so the save must have happened. (A path lfs cannot read cannot be checked and
  -- is trusted: on Windows, one with any character outside ASCII, since the text export gives it in UTF-8 and lfs
  -- takes the code page.)
  local savedBefore = files.modified(projectPath)
  doc.command(app, log, "File.Save")
  -- From here on a failure is told to use File > Revert (main.run).
  ctx.saved = true
  if savedBefore and files.modified(projectPath) == savedBefore then return result(false, "error", M.saveFailed) end

  -- 7. remove
  if resp.remove then
    if not chart then return result(false, "warning", M.noChartToRemove) end
    local okRemove, removed = safe.call(log, "remove", removechart.remove, app, chart, { log = log, fullId = fullId })
    if not okRemove then return result(false, "error", string.format(M.writeFailed, failure(removed), log.path)) end
    if removed.removed and removed.restored == false then return result(true, "warning", M.chartRemovedOptionsLeft) end
    if removed.removed then return result(true, "info", M.chartWasRemoved) end
    return result(false, "warning", M.chartKept)
  end

  -- 8. plan and draw
  -- "Written as": parts written at pitch have their bells an octave above what Dorico stores.
  local records = transpose.atPitch(scan.records, resp.atPitch)
  local thePlan = plan.build(records, { heads = resp.heads, instruments = resp.instruments, mode = resp.mode })
  namedWarnings(thePlan.warnings)
  local extra = {}
  -- A run that charts nothing keeps an existing chart: removing it would need Dorico's delete dialog.
  if #thePlan.sections == 0 then
    return result(false, "warning", report.summary(thePlan, false, extra, chart ~= nil))
  end

  local slots = chartlayout.slots(thePlan.sections)
  local headNames = {}
  for _, h in ipairs(req.noteheads) do headNames[h.id] = h.name end
  local built = chartlayout.build(thePlan.sections, {
    shapes = resp.shapes, colours = resp.colours, heads = resp.heads, headNames = headNames,
  })
  for _, w in ipairs(built.warnings) do extra[#extra + 1] = w end
  local musicKeys = {}
  for _, pl in ipairs(scan.players) do musicKeys[#musicKeys + 1] = pl.key end
  local okWrite, wrote = safe.call(log, "write", writechart.write, app, built,
    { log = log, tempDir = temp, slots = slots, musicKeys = musicKeys, existing = chart, newPage = resp.newPage })
  if not okWrite then return result(false, "error", string.format(M.writeFailed, failure(wrote), log.path)) end

  -- 9. report
  return result(true, "info", report.summary(thePlan, chart ~= nil, extra))
end

function main.run(ctx)
  ctx.log:line("Handbells Used Chart", constants.VERSION, "on Dorico", tostring(ctx.app.versionString))
  local ok, outcome = safe.call(ctx.log, "run", main.chart, ctx)
  if not ok then
    -- Once the project is saved, a failure may have left part of a chart behind, and File > Revert takes it away.
    local text = ctx.saved and M.writeFailed or M.runFailed
    outcome = result(false, "error", string.format(text, failure(outcome), ctx.log.path))
  end
  if outcome.text ~= "" then ctx.show(outcome.kind, outcome.text) end
  return outcome
end

return main
