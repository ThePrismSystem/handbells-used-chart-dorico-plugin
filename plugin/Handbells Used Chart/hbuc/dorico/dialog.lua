-- The bridge to the dialog scripts: the request is written as JSON, the script is started with os.execute (Dorico
-- waits for it, like a modal dialog: docs/dorico-lua-guide.md, section 8), and the response is read back. A
-- missing or unreadable response counts as a cancel. Windows runs dialog/windows.ps1 with PowerShell; a Mac runs
-- dialog/mac.js with osascript, and if osascript comes back at once with no answer, the answer is waited for.
local constants = require("hbuc.constants")
local json = require("hbuc.json")
local shell = require("hbuc.shell")
local files = require("hbuc.dorico.files")

local dialog = {}

-- How long a Mac run waits for an answer that osascript did not wait for.
local WAIT_SECONDS = 600

-- Runs the platform's script with its arguments, already quoted. Returns os.execute's success and the seconds taken.
local function run(ctx, windowsArgs, macArgs)
  local command
  if ctx.isWindows then
    command = "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "
      .. shell.quoteWindows(ctx.root .. "dialog/windows.ps1") .. " " .. windowsArgs
  else
    os.remove(ctx.folders.temp .. "osascript.log") -- so what it holds is this run's
    command = shell.macCommand(ctx.root .. "dialog/mac.js", macArgs, ctx.folders.temp .. "osascript.log")
  end
  ctx.log:line("dialog", command)
  local started = os.time()
  local ok, how, code = os.execute(command)
  local elapsed = os.time() - started
  ctx.log:line("dialog closed", tostring(ok), tostring(how), tostring(code), elapsed .. " s")
  if not ok and not ctx.isWindows then
    local said = files.read(ctx.folders.temp .. "osascript.log")
    if said and said ~= "" then ctx.log:line("osascript said", said:sub(1, 2000)) end
  end
  return ok, elapsed
end

-- A Mac dialog that osascript did not wait for: look for its answer once a second.
local function waitForAnswer(ctx, path)
  ctx.log:line("osascript came back at once with no answer: waiting up to " .. WAIT_SECONDS .. " s for it")
  local started = os.time()
  local text, blocks = shell.poll(function() return files.read(path) end, function() os.execute("/bin/sleep 1") end,
    os.time, WAIT_SECONDS)
  if not blocks then ctx.log:line("sleep did not wait either, so the plug-in waited by itself") end
  ctx.log:line(text and ("the answer came after " .. (os.time() - started) .. " s") or "no answer came")
  return text
end

-- The decoded response, or nil.
function dialog.ask(ctx, req)
  local requestPath = ctx.folders.temp .. "request.json"
  local responsePath = ctx.folders.temp .. "response.json"
  files.write(requestPath, json.encode(req))
  os.remove(responsePath)
  local ok, elapsed = run(ctx, "-Request " .. shell.quoteWindows(requestPath) .. " -Response "
    .. shell.quoteWindows(responsePath), shell.quoteSh(requestPath) .. " " .. shell.quoteSh(responsePath))
  local text = files.read(responsePath)
  -- A script that failed (a non-zero exit) left no dialog up, so there is nothing to wait for.
  if not ctx.isWindows and ok and shell.shouldWait(elapsed, text ~= nil) then text = waitForAnswer(ctx, responsePath) end
  if not text then
    ctx.log:line("no response")
    return nil
  end
  local decoded, raw = pcall(json.decode, text)
  if not decoded then
    ctx.log:line("unreadable response", raw)
    return nil
  end
  if type(raw) == "table" and raw.error then ctx.log:line("the dialog failed", tostring(raw.error)) end
  return raw
end

-- kind: "info", "warning" or "error".
function dialog.show(ctx, kind, text)
  ctx.log:line("message", kind, text)
  local path = ctx.folders.temp .. "message.json"
  files.write(path, json.encode({ title = constants.DIALOG.resultsTitle, kind = kind, text = text,
    ok = constants.DIALOG.ok }))
  run(ctx, "-Message " .. shell.quoteWindows(path), "--message " .. shell.quoteSh(path))
end

return dialog
