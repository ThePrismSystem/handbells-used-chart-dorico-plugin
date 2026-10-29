-- main.run's last resort, with main.chart replaced: what the user is told depends on whether the project had been
-- saved when the run failed. Then main.chart, with Dorico and the layer-2 modules stubbed.
local main = require("hbuc.main")

-- o: {scan = readscore.scan's result, chart = true when one is there, respond = the dialog's answer to the request,
-- choose = the answer to a question (by default its cancel)}. Returns main.chart's outcome, the files written, the
-- commands run, the request the dialog got, the questions asked and the options the read got.
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
    ["hbuc.dorico.readscore"] = { scan = function(_, opts)
      asked.scanOpts = opts
      return o.scan
    end },
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
  return out, writes, commands, asked.req, asked.choices, asked.scanOpts
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

-- B, which has no notes, is the only instrument chosen: the run stops at its report without drawing.
local function chooseB(req)
  return { version = req.version, runId = req.runId, cancelled = false, instruments = { "B" }, mode = req.modes[1],
    heads = {}, shapes = {}, colours = {}, remove = false, atPitch = {} }
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
}
