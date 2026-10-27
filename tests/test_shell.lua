-- Quoting for the shells the dialog starts through, and when the plug-in waits for the Mac dialog's answer.
local shell = require("hbuc.shell")

return {
  quote_sh = function(t)
    t:eq(shell.quoteSh("It's"), "'It'\\''s'", "a quote closes, is escaped and reopens")
    t:eq(shell.quoteSh("/Users/u/Library/Application Support/x.json"), "'/Users/u/Library/Application Support/x.json'")
    t:eq(shell.quoteSh("$HOME `a` \"b\" \\c"), "'$HOME `a` \"b\" \\c'", "nothing else is special inside single quotes")
  end,
  quote_windows = function(t)
    t:eq(shell.quoteWindows("C:/Users/u/AppData/Local/Temp/hbuc/request.json"),
      '"C:\\Users\\u\\AppData\\Local\\Temp\\hbuc\\request.json"')
  end,
  mac_command_keeps_osascript_errors = function(t)
    t:eq(shell.macCommand("/p/dialog/mac.js", "'a' 'b'", "/tmp/hbuc/osascript.log"),
      "/usr/bin/osascript -l JavaScript '/p/dialog/mac.js' 'a' 'b' 2>'/tmp/hbuc/osascript.log'")
  end,
  poll_finds_the_answer_with_a_working_sleep = function(t)
    local clock, sleeps = 0, 0
    local answer, blocks = shell.poll(function() return clock >= 3 and "answer" or nil end,
      function() sleeps = sleeps + 1; clock = clock + 1 end, function() return clock end, 600)
    t:eq(answer, "answer")
    t:eq(sleeps, 3, "one sleep a second")
    t:eq(blocks, true)
  end,
  poll_gives_up_at_the_limit = function(t)
    local clock = 0
    local answer = shell.poll(function() return nil end, function() clock = clock + 1 end, function() return clock end, 5)
    t:eq(answer, nil)
    t:eq(clock, 5)
  end,
  poll_waits_in_lua_when_sleep_does_not_block = function(t)
    -- an os.execute that does not wait makes sleep come back at once: starting it again would start a process
    -- after process for as long as the dialog is up
    local reads, sleeps = 0, 0
    local function now() reads = reads + 1; return math.floor(reads / 10) end -- time passes as the clock is read
    local answer, blocks = shell.poll(function() return now() >= 4 and "answer" or nil end,
      function() sleeps = sleeps + 1 end, now, 600)
    t:eq(answer, "answer")
    t:eq(sleeps, 1, "sleep is tried once")
    t:eq(blocks, false)
  end,
  should_wait = function(t)
    t:eq(shell.shouldWait(0, false), true, "back at once with no answer: the dialog is still up")
    t:eq(shell.shouldWait(1, false), true)
    t:eq(shell.shouldWait(5, false), false, "a dialog that was up a while and left nothing was closed")
    t:eq(shell.shouldWait(0, true), false, "an answer is there")
  end,
}
