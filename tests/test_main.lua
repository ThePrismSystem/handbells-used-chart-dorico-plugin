-- main.run's last resort, with main.chart replaced: what the user is told depends on whether the project had been
-- saved when the run failed. Then main.chart's MusicXML step, with Dorico and the layer-2 modules stubbed.
local constants = require("hbuc.constants")
local main = require("hbuc.main")

local M = constants.MESSAGES

-- o: {step = musicxmlstep.run's outcome, scan = readscore.scan's, chart = true when one is there, respond = the
-- dialog's answer to the request, choose = the answer to a question (by default its cancel)}. Returns main.chart's
-- outcome, the files written, the commands run, the request the dialog got and the questions asked.
local function chartRun(o)
  local writes, commands, asked = {}, {}, { choices = {} }
  local stubs = {
    ["hbuc.textexport"] = { projectPath = function() return "C:/p/Bells.dorico" end },
    ["hbuc.chartlayout"] = { fullScoreLayout = function() return "full" end },
    ["hbuc.dorico.doc"] = {
      exportText = function() return "" end,
      command = function(_, _, text) commands[#commands + 1] = text end,
      playerKey = function(pl) return pl.key end,
      layouts = function() return {} end,
    },
    ["hbuc.dorico.files"] = {
      read = function() return nil end,
      write = function(path, text) writes[path] = text end,
      modified = function() return nil end,
    },
    ["hbuc.dorico.findchart"] = { find = function()
      return o.chart and { status = "ok", flowId = "9", marker = { chartPlayers = {} } } or { status = "none" }
    end },
    ["hbuc.dorico.readscore"] = { scan = function() return o.scan end },
    ["hbuc.dorico.musicxmlstep"] = { run = function() return o.step end },
    ["hbuc.dorico.removechart"] = { remove = function() return { removed = true } end },
    ["hbuc.dorico.writechart"] = { write = function() return {} end },
    ["hbuc.dorico.safe"] = { call = function(_, _, fn, ...) return pcall(fn, ...) end },
  }
  local saved = { ["hbuc.main"] = package.loaded["hbuc.main"] }
  for name, stub in pairs(stubs) do
    saved[name] = package.loaded[name]
    package.loaded[name] = stub
  end
  package.loaded["hbuc.main"] = nil
  local ctx = {
    app = { versionString = "6.0.10", currentScore = { players = { { key = "k1" } } }, currentLayoutID = "full" },
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
  return out, writes, commands, asked.req, asked.choices
end

-- Flows 1 and 2, each with one note of A's whose head was changed in Dorico; B has no notes.
local function scan()
  local dumped = {
    { flowId = "1", instrument = "A", spelling = "C5", pos = 0, grace = false },
    { flowId = "2", instrument = "A", spelling = "D5", pos = 0, grace = false },
  }
  local read = {}
  for i, d in ipairs(dumped) do
    read[i] = { flowId = d.flowId, instrument = "A", spelling = d.spelling, pos = 0, grace = false, head = "", colour = "",
      headUnreadable = true, colourUnreadable = false }
  end
  return { players = { { key = "k1", name = "A" }, { key = "k2", name = "B" } }, records = {}, unread = 0, merged = 0,
    dumped = dumped, read = read, flowNumbers = { ["1"] = 1, ["2"] = 2 } }
end

-- Flow 1's export, with notes on: a diamond C5 at 0, and whatever else.
local function flowOne(...)
  local notes = { { pos = 0, pitch = 72, diatonic = 35, grace = false, head = "diamond", colour = "" }, ... }
  return { parts = { { name = "A", notes = notes } } }
end

-- B, which has no notes, is the only instrument chosen: the run stops at its report without drawing.
local function chooseB(req)
  return { version = req.version, runId = req.runId, cancelled = false, instruments = { "B" }, mode = req.modes[1],
    heads = {}, shapes = {}, colours = {}, remove = false, atPitch = {} }
end

local function has(text, line)
  return text:find(line, 1, true) ~= nil
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
  the_musicxml_step_ends_the_run_on_cancel_or_error = function(t)
    local out, _, _, req = chartRun({ scan = scan(), step = { status = "cancel" } })
    t:eq(out.kind, "info")
    t:eq(out.text, "")
    t:eq(req, nil, "no dialog")
    out = chartRun({ scan = scan(), step = { status = "error", text = "No good." } })
    t:eq(out.kind, "error")
    t:eq(out.text, "No good.")
  end,
  a_file_that_pairs_with_no_flow_changes_nothing = function(t)
    local other = { parts = { { name = "A", notes = { { pos = 4, pitch = 72, diatonic = 35, grace = false } } } } }
    local out, writes, commands, req = chartRun({ scan = scan(), step = { status = "files", files = { other } } })
    t:eq(out.text, string.format(M.musicxmlMismatch, 1), "names the first flow that needs one")
    t:eq(req, nil, "no dialog")
    t:eq(next(writes), nil, "nothing written")
    t:eq(#commands, 2, "Write mode only, no save")
  end,
  the_files_heads_reach_the_dialog_and_a_flow_without_one_is_named = function(t)
    local out, _, _, req, choices = chartRun({ scan = scan(), step = { status = "files", files = { flowOne() } },
      respond = chooseB })
    t:eq(#choices, 1, "asked about flow 2's note, and kept it separate")
    local ids = {}
    for _, h in ipairs(req.noteheads) do ids[h.id] = true end
    t:ok(ids["noteheadset.diamondNoteheads"], "flow 1's head, from the file")
    t:ok(ids["noteheadset.notInMusicXML"], "flow 2's, which no file holds")
    t:ok(has(out.text, string.format(M.musicxmlMissingFlow, "2", constants.NOT_IN_MUSICXML_NAME)), out.text)
    t:ok(not has(out.text, "couldn't be found"), "every changed note in flow 1 was in its file")
  end,
  a_note_musicxml_couldnt_name_can_join_a_notehead_before_the_dialog = function(t)
    local out, _, _, req, choices = chartRun({ scan = scan(), step = { status = "files", files = { flowOne() } },
      respond = chooseB, choose = function() return "noteheadset.diamondNoteheads" end })
    t:eq(choices[1].text, string.format(M.musicxmlUnnamedNote, "D5") .. "\n\n"
      .. string.format(M.musicxmlGroupWithOne, "Diamond Noteheads", constants.NOT_IN_MUSICXML_NAME),
      "flow 2's note, by the pitch Lua has, since no file holds it")
    local ids = {}
    for _, h in ipairs(req.noteheads) do ids[h.id] = true end
    t:ok(ids["noteheadset.diamondNoteheads"])
    t:ok(not ids["noteheadset.notInMusicXML"], "it went in with the diamonds")
    t:ok(has(out.text, string.format(M.musicxmlMissingFlow, "2", "Diamond Noteheads")), out.text)
  end,
  a_question_that_cannot_be_shown_says_so = function(t)
    local out, _, _, req = chartRun({ scan = scan(), step = { status = "files", files = { flowOne() } },
      choose = function() return nil end })
    t:eq(out.kind, "error")
    t:eq(out.text, constants.DIALOG.dialogFailed)
    t:eq(req, nil, "no dialog")
  end,
  changed_notes_a_paired_file_lacks_are_counted = function(t)
    local s = scan()
    s.dumped[2].flowId, s.read[2].flowId = "1", "1"
    s.read[2].pos = 5
    local out = chartRun({ scan = s, step = { status = "files",
      files = { flowOne({ pos = 0, pitch = 74, diatonic = 36, grace = false }) } }, respond = chooseB })
    t:ok(has(out.text, string.format(M.musicxmlUnmatched, 1, constants.NOT_IN_MUSICXML_NAME)), out.text)
  end,
  remove_from_the_musicxml_message_skips_the_dialog_and_the_settings = function(t)
    local out, writes, commands, req = chartRun({ scan = scan(), step = { status = "remove" }, chart = true })
    t:eq(out.text, M.chartWasRemoved)
    t:eq(req, nil, "no dialog")
    t:eq(writes["d/settings.json"], nil, "the choices are left as they were")
    t:eq(commands[#commands], "File.Save", "saved before the removal")
  end,
}
