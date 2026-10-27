-- Shared by the in-Dorico case scripts (tests/dorico/case_*.lua), which run through tools/dorico/run_lua.py on
-- scratch copies only. A case runs the plug-in's own code with a test context: the real Dorico app, folders in the
-- run folder, and a scripted dialog that records the request it was given.
local files = require("hbuc.dorico.files")
local safe = require("hbuc.dorico.safe")

local cases = {}

local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
cases.repo = here .. "../../../"
cases.root = cases.repo .. "plugin/Handbells Used Chart/"

function cases.runFolder()
  return (require("rundir")():gsub("\\", "/"))
end

-- overrides.respond(req) returns the raw response the dialog would have written (nil = cancelled).
function cases.context(p, overrides)
  overrides = overrides or {}
  local run = cases.runFolder()
  local folders = { data = run .. "plugin/data/", temp = run .. "plugin/temp/" }
  files.ensureDir(folders.data)
  files.ensureDir(folders.temp)
  local shown = {}
  p.facts.shown = shown
  local ctx = {
    app = DoApp.DoApp(),
    root = cases.root,
    isWindows = package.config:sub(1, 1) == "\\",
    folders = folders,
    log = safe.logger(folders.data .. "run.log"),
  }
  ctx.dialog = function(req)
    p.facts.request = req
    if overrides.respond then return overrides.respond(req) end
    return nil
  end
  ctx.show = function(kind, text) shown[#shown + 1] = { kind = kind, text = text } end
  return ctx
end

-- "<flow id>=<dump notes>n/<players>p" for every flow: a cheap fingerprint of the music.
function cases.summary(score)
  local dump = require("hbuc.dump")
  local parts = {}
  for _, f in ipairs(score.flows) do
    local n = 0
    for _, s in ipairs(f.voiceStreams) do n = n + #dump.notes(dump.parse(s:dump())) end
    parts[#parts + 1] = f.id .. "=" .. n .. "n/" .. #f.players .. "p"
  end
  return table.concat(parts, ",")
end

return cases
