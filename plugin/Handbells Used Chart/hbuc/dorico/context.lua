-- Everything a run touches outside its own logic, for the real Script-menu run. Tests build their own context
-- (tests/dorico/lib/cases.lua) with a scripted dialog in place of the real one.
local constants = require("hbuc.constants")
local files = require("hbuc.dorico.files")
local guards = require("hbuc.guards")
local safe = require("hbuc.dorico.safe")

local context = {}

function context.real(root)
  local isWindows = package.config:sub(1, 1) == "\\"
  local env = {}
  for _, name in ipairs({ "APPDATA", "TEMP", "HOME", "TMPDIR" }) do env[name] = os.getenv(name) end
  local folders = guards.folders(env, isWindows)
  files.ensureDir(folders.data)
  files.ensureDir(folders.temp)
  local ctx = {
    app = DoApp.DoApp(),
    root = root,
    isWindows = isWindows,
    folders = folders,
    log = safe.logger(folders.data .. "run.log"),
  }
  -- what a Mac run report needs first
  ctx.log:line("platform", isWindows and "Windows" or "Mac", "lfs " .. (pcall(require, "lfs") and "found" or "missing"),
    "data " .. folders.data, "temp " .. folders.temp)
  ctx.dialog = function(req) return require("hbuc.dorico.dialog").ask(ctx, req) end
  ctx.show = function(kind, text) require("hbuc.dorico.dialog").show(ctx, kind, text) end
  ctx.choose = function(choice) return require("hbuc.dorico.dialog").choose(ctx, choice) end
  ctx.pick = function(pick) return require("hbuc.dorico.dialog").pick(ctx, pick) end
  return ctx
end

-- The last resort for a run that could not start (no folder for its files, a module that will not load): the error
-- goes in the results window rather than nowhere. Every step is guarded, since anything may be what failed. env and
-- isWindows are for tests.
function context.failed(root, err, env, isWindows)
  if isWindows == nil then isWindows = package.config:sub(1, 1) == "\\" end
  if not env then
    env = {}
    for _, name in ipairs({ "TEMP", "TMP", "TMPDIR" }) do env[name] = os.getenv(name) end
  end
  local temp = guards.anyTemp(env, isWindows)
  if not temp then return end
  pcall(files.ensureDir, temp)
  local ctx = { root = root, isWindows = isWindows, folders = { data = temp, temp = temp },
    log = safe.logger(temp .. "run.log") }
  ctx.log:line("the plug-in could not start:", tostring(err))
  local text = string.format(constants.MESSAGES.startFailed, tostring(safe.firstLine(err)))
  pcall(function() require("hbuc.dorico.dialog").show(ctx, "error", text) end)
end

return context
