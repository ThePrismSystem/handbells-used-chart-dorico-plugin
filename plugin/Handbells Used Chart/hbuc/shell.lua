-- Quoting for the shells the dialog scripts start through (cmd on Windows, sh on a Mac), and when the plug-in
-- waits for the Mac dialog's answer.
local shell = {}

-- For sh: inside single quotes nothing is special, and a quote is written '\'' (close, escaped quote, reopen).
function shell.quoteSh(text)
  return "'" .. (tostring(text):gsub("'", "'\\''")) .. "'"
end

-- For cmd: double-quoted, with Windows' backslashes.
function shell.quoteWindows(path)
  return '"' .. (tostring(path):gsub("/", "\\")) .. '"'
end

-- The Mac dialog's command, with osascript's full path (an app started from the Finder has a short PATH).
-- osascript's own errors (one the script could not catch, or a syntax error) go to errorPath, since Dorico shows
-- nobody its output.
function shell.macCommand(scriptPath, args, errorPath)
  return "/usr/bin/osascript -l JavaScript " .. shell.quoteSh(scriptPath) .. " " .. args .. " 2>"
    .. shell.quoteSh(errorPath)
end

-- Looks for an answer once a second until limit seconds have passed: read() gives the answer or nil, sleep() should
-- take a second, now() counts whole seconds. This runs only when os.execute did not wait for osascript, and then
-- it may not wait for sleep either: a sleep that came back at once is not tried again (that would start a process
-- after process), and the second is waited out here instead. Returns the answer or nil, and whether sleep blocked.
function shell.poll(read, sleep, now, limit)
  local started, blocks = now(), true
  while now() - started < limit do
    local before = now()
    if blocks then
      sleep()
      blocks = now() ~= before
    end
    if not blocks then
      while now() == before do end
    end
    local answer = read()
    if answer then return answer, blocks end
  end
  return nil, blocks
end

-- os.execute should wait for osascript, which waits for the dialog (not yet confirmed on a Mac).
-- If it came back with no answer before anyone could have used the dialog, the dialog is taken to be still up.
function shell.shouldWait(elapsedSeconds, responseExists)
  return not responseExists and elapsedSeconds < 2
end

return shell
