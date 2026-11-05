-- main.run's last resort, with main.chart replaced: what the user is told depends on whether the project had been
-- saved when the run failed. Then main.chart, with Dorico and the layer-2 modules stubbed.
local main = require("hbuc.main")

-- o: {scan = readscore.scan's result, scanError = what it raises instead, chart = true when one is there (or the
-- whole of findchart's answer), respond = the dialog's answer to the request, choose = the answer to a question (by
-- default its cancel), version = Dorico's, players = the score's, projectPath = the text export's, layoutId = the
-- one on screen, stamp = files.stamp, removed = removechart's answer, removeError and writeError = what those raise
-- instead}. Returns main.chart's outcome, the files written, the commands run, the request the dialog got, the
-- questions asked, and the options the read, the write and the remove got.
local function chartRun(o)
  local writes, commands, asked = {}, {}, { choices = {} }
  local chart = o.chart == true and { status = "ok", flowId = "9", marker = { chartPlayers = {} } } or o.chart
  -- The chart's layout on screen is Dorico's; drawing uses the real slots and build.
  local layout = setmetatable({ fullScoreLayout = function() return "full" end },
    { __index = require("hbuc.chartlayout") })
  local stubs = {
    ["hbuc.textexport"] = { projectPath = function() return o.projectPath or "C:/p/Bells.dorico" end },
    ["hbuc.chartlayout"] = layout,
    ["hbuc.dorico.doc"] = {
      exportText = function() return "" end,
      command = function(_, _, text) commands[#commands + 1] = text end,
      playerKey = function(pl) return pl.key end,
      layouts = function() return {} end,
    },
    ["hbuc.dorico.files"] = {
      read = function() return nil end,
      write = function(path, text) writes[path] = text end,
      stamp = o.stamp or function() return nil end,
    },
    ["hbuc.dorico.findchart"] = { find = function() return chart or { status = "none" } end },
    ["hbuc.dorico.readscore"] = { scan = function(_, opts)
      asked.scanOpts = opts
      if o.scanError then error(o.scanError, 0) end
      return o.scan
    end },
    ["hbuc.dorico.removechart"] = { remove = function(_, _, opts)
      asked.removeOpts = opts
      if o.removeError then error(o.removeError, 0) end
      return o.removed or { removed = true }
    end },
    ["hbuc.dorico.writechart"] = { write = function(_, _, opts)
      asked.writeOpts = opts
      if o.writeError then error(o.writeError, 0) end
      return {}
    end },
    ["hbuc.dorico.safe"] = { call = function(_, _, fn, ...) return pcall(fn, ...) end },
  }
  local saved = { ["hbuc.main"] = package.loaded["hbuc.main"] }
  for name, stub in pairs(stubs) do
    saved[name] = package.loaded[name]
    package.loaded[name] = stub
  end
  package.loaded["hbuc.main"] = nil
  local ctx = {
    app = { versionString = o.version or "6.0.10", currentScore = { players = o.players or { { key = "k1" } } },
      currentLayoutID = o.layoutId or "full" },
    log = { path = "run.log", line = function() end }, folders = { temp = "t/", data = "d/" },
    dialog = function(req)
      asked.req = req
      return o.respond and o.respond(req) or nil
    end,
    choose = function(question)
      asked.choices[#asked.choices + 1] = question
      if o.choose then return o.choose(question) end
      return question.cancel
    end,
  }
  local ok, out = pcall(function() return require("hbuc.main").chart(ctx) end)
  for name, m in pairs(saved) do package.loaded[name] = m end
  if not ok then error(out, 0) end
  return out, writes, commands, asked.req, asked.choices, asked.scanOpts, asked.writeOpts, asked.removeOpts
end

-- A, with a C5 and a D5, and B with nothing.
local function scan()
  local records = {}
  for i, pitch in ipairs({ 72, 74 }) do
    records[i] = { pitch = pitch, diatonic = 34 + i, head = "noteheadset.default", colour = "", instrument = "A",
      grace = false }
  end
  return { players = { { key = "k1", name = "A" }, { key = "k2", name = "B" } }, records = records }
end

-- A's notes with these heads, as {id, count} pairs
local function headsScan(...)
  local s = scan()
  s.records = {}
  for _, pair in ipairs({ ... }) do
    for _ = 1, pair[2] do
      s.records[#s.records + 1] = { pitch = 72, diatonic = 35, head = pair[1], colour = "", instrument = "A",
        grace = false }
    end
  end
  return s
end

local function offered(req)
  local out = {}
  for _, h in ipairs(req.noteheads) do out[h.id] = true end
  return out
end

local DEFAULT, DIAMOND, OLD = "noteheadset.default", "noteheadset.diamondNoteheads", "noteheadset.oldDiamondNoteheads"
local M = require("hbuc.constants").MESSAGES
local shapes = require("hbuc.shapes")

-- B, which has no notes, is the only instrument chosen: the run stops at its report without drawing.
local function chooseB(req)
  return { version = req.version, runId = req.runId, cancelled = false, instruments = { "B" }, mode = req.modes[1],
    heads = {}, shapes = {}, colours = {}, remove = false, atPitch = {} }
end

-- A, with its default noteheads as the handbells; over replaces any of the answer's fields.
local function chooseA(req, over)
  local resp = { version = req.version, runId = req.runId, cancelled = false, instruments = { "A" },
    mode = req.modes[1], heads = { bells = DEFAULT }, shapes = {}, colours = {}, remove = false, atPitch = {},
    newPage = true }
  for k, v in pairs(over or {}) do resp[k] = v end
  return resp
end

local function chooseRemove(req) return chooseA(req, { remove = true }) end

local function has(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end

local function runWith(chart)
  local ctx = { app = { versionString = "6.0.10" }, log = { path = "run.log", line = function() end } }
  ctx.show = function(kind, text) ctx.shown = { kind = kind, text = text } end
  local real = main.chart
  main.chart = chart
  local ok, out = pcall(main.run, ctx)
  main.chart = real
  if not ok then error(out, 0) end
  return ctx, out
end

return {
  failure_before_the_save_says_nothing_changed = function(t)
    local ctx, out = runWith(function() error("boom") end)
    t:eq(out.kind, "error")
    t:eq(out.text, "The plug-in stopped with an error, so nothing was changed: boom\n\nThe run log is at run.log.")
    t:eq(ctx.shown.text, out.text, "and shows it")
  end,
  failure_after_the_save_points_to_revert = function(t)
    local _, out = runWith(function(ctx) ctx.saved = true; error("boom") end)
    t:eq(out.text, "The chart could not be finished: boom\n\nUse File > Revert to return to the project as it was"
      .. " before the run. The run log is at run.log.")
  end,
  the_read_gets_the_full_score_and_the_temp_folder = function(t)
    local out, _, _, req, _, opts = chartRun({ scan = scan(), respond = chooseB })
    t:eq(opts.layoutId, "full", "the full score layout, which the guards made sure is on screen")
    t:eq(opts.tempDir, "t/")
    t:ok(req, "then the dialog")
    t:eq(out.kind, "warning", "B has nothing to chart")
  end,
  a_read_that_fails_says_so_and_asks_nothing = function(t)
    local out, writes, _, req, choices = chartRun({ scanError = "zip: CRC mismatch for score.dtn" })
    t:eq(out.kind, "error")
    t:eq(out.text, "The plug-in could not read this project's music, so nothing was changed: zip: CRC mismatch for"
      .. " score.dtn\n\nThe run log is at run.log.")
    t:eq(req, nil, "no dialog")
    t:eq(#choices, 0, "no question")
    t:eq(next(writes), nil, "no settings written")
  end,
  a_rare_set_can_join_the_common_one_before_the_dialog = function(t)
    local _, _, _, req, choices = chartRun({ scan = headsScan({ DIAMOND, 6 }, { OLD, 1 }), respond = chooseB,
      choose = function() return "combine" end })
    t:eq(#choices, 1, "one question")
    t:ok(choices[1].text:find("Old-Style Diamond Noteheads: 1 note", 1, true), choices[1].text)
    t:ok(offered(req)[DIAMOND], "the diamond is offered")
    t:ok(not offered(req)[OLD], "and the old-style one went in with it")
  end,
  keep_separate_offers_both = function(t)
    local _, _, _, req = chartRun({ scan = headsScan({ DIAMOND, 6 }, { OLD, 1 }), respond = chooseB })
    t:ok(offered(req)[DIAMOND] and offered(req)[OLD], "both offered")
  end,
  a_question_that_cannot_be_shown_says_so = function(t)
    local out, _, _, req = chartRun({ scan = headsScan({ DIAMOND, 6 }, { OLD, 1 }),
      choose = function() return nil end })
    t:eq(out.kind, "error")
    t:eq(out.text, require("hbuc.constants").DIALOG.dialogFailed)
    t:eq(req, nil, "no dialog")
  end,
  common_sets_ask_nothing = function(t)
    local _, _, _, _, choices = chartRun({ scan = headsScan({ DIAMOND, 6 }, { OLD, 5 }), respond = chooseB })
    t:eq(#choices, 0)
  end,

  -- Every way a run can end.
  an_untested_dorico_is_refused = function(t)
    local out, _, commands = chartRun({ version = "5.1.70", scan = scan() })
    t:eq(out.ok, false)
    t:eq(out.kind, "error")
    t:eq(out.text, string.format(M.untestedDorico, "5.1.70"))
    t:eq(#commands, 0, "nothing is done in Dorico")
  end,
  no_players_is_no_project = function(t)
    local out = chartRun({ players = {}, scan = scan() })
    t:eq(out.kind, "error")
    t:eq(out.text, M.noProject)
  end,
  an_unsaved_project_is_refused = function(t)
    local out = chartRun({ projectPath = "", scan = scan() })
    t:eq(out.kind, "warning")
    t:eq(out.text, M.notSaved)
  end,
  a_part_on_screen_is_refused = function(t)
    local out = chartRun({ layoutId = "part", scan = scan() })
    t:eq(out.kind, "warning")
    t:eq(out.text, M.notFullScore)
  end,
  a_chart_it_cannot_identify_is_left_alone = function(t)
    local out, _, _, req = chartRun({ chart = { status = "invalid", reason = "its marker is damaged" }, scan = scan() })
    t:eq(out.kind, "error")
    t:eq(out.text, string.format(M.chartUnidentified, "its marker is damaged"))
    t:eq(req, nil, "no dialog")
  end,
  an_existing_chart_is_skipped_by_the_read = function(t)
    local found = { status = "ok", flowId = "9", marker = { chartPlayers = { "c1", "c2" } } }
    local _, _, _, req, _, opts = chartRun({ chart = found, scan = scan(), respond = chooseB })
    t:eq(opts.skipFlowId, "9", "the chart's flow")
    t:ok(opts.skipKeys.c1 and opts.skipKeys.c2, "and its players")
    t:eq(req.chartExists, true, "the dialog is told there is one")
  end,
  a_cancelled_dialog_says_nothing = function(t)
    local out, writes = chartRun({ scan = scan() })
    t:eq(out.ok, false)
    t:eq(out.kind, "info")
    t:eq(out.text, "", "nothing to show")
    t:eq(next(writes), nil, "no settings written")
  end,
  a_dialog_that_fails_counts_as_a_cancel = function(t)
    local out = chartRun({ scan = scan(), respond = function() error("no PowerShell") end })
    t:eq(out.kind, "info")
    t:eq(out.text, "")
  end,
  two_kinds_on_one_notehead_are_refused = function(t)
    local out, writes = chartRun({ scan = scan(), respond = function(req)
      return chooseA(req, { heads = { bells = DEFAULT, chimes = DEFAULT } })
    end })
    t:eq(out.kind, "error")
    t:eq(out.text, "More than one instrument is set to the " .. shapes.displayName(DEFAULT) .. " notehead. "
      .. M.sameNoteheadChosen)
    t:eq(next(writes), nil, "refused before anything is saved")
  end,
  no_instrument_chosen_is_refused = function(t)
    local out = chartRun({ scan = scan(), respond = function(req) return chooseA(req, { instruments = {} }) end })
    t:eq(out.kind, "error")
    t:eq(out.text, M.noInstrumentSelected)
  end,
  a_save_that_did_not_happen_stops_the_run = function(t)
    local out, writes, commands = chartRun({ scan = scan(), respond = chooseA, stamp = function() return 100 end })
    t:eq(out.kind, "error")
    t:eq(out.text, M.saveFailed)
    t:ok(has(commands, "File.Save"), "it tried")
    t:ok(writes["d/settings.json"], "the choices are remembered first")
  end,
  a_save_that_changed_the_project_goes_on = function(t)
    local stamps = 0
    local out = chartRun({ scan = scan(), respond = chooseA, stamp = function()
      stamps = stamps + 1
      return stamps
    end })
    t:eq(out.ok, true)
    t:eq(stamps, 2, "checked before and after")
  end,
  remove_without_a_chart_warns = function(t)
    local out = chartRun({ scan = scan(), respond = chooseRemove })
    t:eq(out.ok, false)
    t:eq(out.kind, "warning")
    t:eq(out.text, M.noChartToRemove)
  end,
  a_remove_that_fails_points_to_revert = function(t)
    local out = chartRun({ chart = true, scan = scan(), respond = chooseRemove, removeError = "no flow 9" })
    t:eq(out.kind, "error")
    t:eq(out.text, string.format(M.writeFailed, "no flow 9", "run.log"))
  end,
  removed_with_its_options_left_warns = function(t)
    local out = chartRun({ chart = true, scan = scan(), respond = chooseRemove,
      removed = { removed = true, restored = false } })
    t:eq(out.ok, true)
    t:eq(out.kind, "warning")
    t:eq(out.text, M.chartRemovedOptionsLeft)
  end,
  removed_says_so = function(t)
    local out = chartRun({ chart = true, scan = scan(), respond = chooseRemove })
    t:eq(out.ok, true)
    t:eq(out.kind, "info")
    t:eq(out.text, M.chartWasRemoved)
  end,
  removing_finds_player_ids_in_the_temp_folder = function(t)
    local _, _, _, _, _, _, _, removeOpts = chartRun({ chart = true, scan = scan(), respond = chooseRemove })
    t:eq(removeOpts.tempDir, "t/")
  end,
  nothing_removed_keeps_the_chart = function(t)
    local out = chartRun({ chart = true, scan = scan(), respond = chooseRemove, removed = { removed = false } })
    t:eq(out.ok, false)
    t:eq(out.kind, "warning")
    t:eq(out.text, M.chartKept)
  end,
  a_chart_is_drawn_and_reported = function(t)
    local out, _, _, _, _, _, wrote = chartRun({ scan = scan(), respond = chooseA })
    t:eq(out.ok, true)
    t:eq(out.kind, "info")
    t:eq(out.text, "Handbells Used: 2")
    t:eq(wrote.newPage, true)
    t:eq(table.concat(wrote.musicKeys, ","), "k1,k2", "every player's music follows the chart")
    t:eq(wrote.existing, nil, "no chart to replace")
  end,
  a_write_that_fails_points_to_revert = function(t)
    local out = chartRun({ scan = scan(), respond = chooseA, writeError = "no room on the page" })
    t:eq(out.kind, "error")
    t:eq(out.text, string.format(M.writeFailed, "no room on the page", "run.log"))
  end,
  unrecognised_noteheads_are_named_as_the_dialog_lists_them = function(t)
    local out = chartRun({ scan = headsScan({ DEFAULT, 2 }, { DIAMOND, 1 }), respond = chooseA })
    t:ok(out.text:find("skipped: " .. shapes.displayName(DIAMOND), 1, true), out.text)
    t:ok(not out.text:find(DIAMOND, 1, true), "not by its id")
  end,
}
