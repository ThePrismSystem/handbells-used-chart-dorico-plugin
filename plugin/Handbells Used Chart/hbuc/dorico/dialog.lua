-- The bridge to the dialog scripts: the request is written as JSON, the script is started with os.execute (Dorico
-- waits for it, like a modal dialog: docs/dorico-lua-guide.md, section 8), and the response is read back. A
-- missing or unreadable response to the settings dialog counts as a cancel; for the MusicXML step's message and
-- picker it is a failure, which the run reports. Windows runs dialog/windows.ps1 with PowerShell; a Mac runs
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

-- One exchange with the script: payload goes to <temp>/<name>, the script runs with windowsFlag or macFlag before
-- that file and the response file, and its decoded answer comes back, or nil when there was none to read.
local function exchange(ctx, name, payload, windowsFlag, macFlag)
  local path = ctx.folders.temp .. name
  local responsePath = ctx.folders.temp .. "response.json"
  files.write(path, json.encode(payload))
  os.remove(responsePath)
  local ok, elapsed = run(ctx, windowsFlag .. " " .. shell.quoteWindows(path) .. " -Response "
    .. shell.quoteWindows(responsePath), macFlag .. shell.quoteSh(path) .. " " .. shell.quoteSh(responsePath))
  local text = files.read(responsePath)
  -- A script that failed (a non-zero exit) left no dialog up, so there is nothing to wait for.
  if not ctx.isWindows and ok and shell.shouldWait(elapsed, text ~= nil) then text = waitForAnswer(ctx, responsePath) end
  if not text then
    ctx.log:line("no answer")
    return nil
  end
  local decoded, raw = pcall(json.decode, text)
  if not decoded or type(raw) ~= "table" then
    ctx.log:line("unreadable answer", tostring(raw))
    return nil
  end
  -- a script whose window failed answers Cancel or no files, with the reason
  if raw.error then ctx.log:line("the dialog failed", tostring(raw.error)) end
  return raw
end

-- The decoded response, or nil. One that carries an error is a cancel, which request.parse sees.
function dialog.ask(ctx, req)
  return exchange(ctx, "request.json", req, "-Request", "")
end

-- A message with several buttons. choice: {title, text, buttons = {{id, label}}, cancel = id}. Returns the pressed
-- button's id, or nil when the window failed or nothing answered.
function dialog.choose(ctx, choice)
  local raw = exchange(ctx, "choice.json", choice, "-Choice", "--choice ")
  if not raw or raw.error or type(raw.choice) ~= "string" then return nil end
  return raw.choice
end

local function hex(s)
  return (tostring(s):gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

local function unhex(h)
  return (h:gsub("%x%x", function(x) return string.char(tonumber(x, 16)) end))
end

-- A file picker. pick: {title, folder, files (names preselected), filter = {name, extensions}}; only the Windows
-- picker preselects files and filters by extension. Returns the chosen paths and the same paths in UTF-8 for
-- messages: none for a cancel, nil when the window failed or nothing answered. On Windows, Dorico's io.open and
-- lfs take a path only in the system's code page (spike/50_paths.py), while JSON is UTF-8, so the paths also travel
-- as their bytes, in hex: the script reads folderBytes and filesBytes, and answers each chosen path's code page bytes
-- in its own filesBytes.
function dialog.pick(ctx, pick)
  local payload = {}
  for k, v in pairs(pick) do payload[k] = v end
  payload.folderBytes = hex(pick.folder or "")
  payload.filesBytes = {}
  for i, name in ipairs(pick.files or {}) do payload.filesBytes[i] = hex(name) end
  local raw = exchange(ctx, "pick.json", payload, "-Pick", "--pick ")
  if not raw or raw.error then return nil end
  local shown = type(raw.files) == "table" and raw.files or {}
  local bytes = type(raw.filesBytes) == "table" and raw.filesBytes
  local paths, names = {}, {}
  for i, p in ipairs(bytes or shown) do
    if type(p) == "string" then
      paths[#paths + 1] = bytes and unhex(p) or p
      names[#names + 1] = type(shown[i]) == "string" and shown[i] or paths[#paths]
    end
  end
  return paths, names
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
