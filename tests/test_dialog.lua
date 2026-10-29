-- The results window's message file, with the file helpers and os.execute stubbed, so nothing is shown.
local json = require("hbuc.json")

local function showWith(isWindows)
  local written, ran
  local names = { "hbuc.dorico.files", "hbuc.dorico.dialog" }
  local saved = {}
  for _, name in ipairs(names) do saved[name] = package.loaded[name] end
  package.loaded["hbuc.dorico.files"] = { write = function(_, text) written = text end, read = function() end }
  package.loaded["hbuc.dorico.dialog"] = nil
  local execute = os.execute
  -- a stand-in for os.execute, put back below
  os.execute = function(command) ran = command; return true, "exit", 0 end -- luacheck: ignore 122
  local ok, err = pcall(function()
    local ctx = { isWindows = isWindows, root = "r/", folders = { temp = "t/" }, log = { line = function() end } }
    require("hbuc.dorico.dialog").show(ctx, "info", "Done")
  end)
  os.execute = execute -- luacheck: ignore 122
  for _, name in ipairs(names) do package.loaded[name] = saved[name] end
  if not ok then error(err, 0) end
  return json.decode(written), ran
end

-- One choice or pick exchange with os.execute and the files stubbed: answer is what the script "writes" to the
-- response file (nil for none). Returns the result, the request file's JSON and the command run.
local function exchange(isWindows, fn, answer, logged)
  local written, ran = {}, nil
  local names = { "hbuc.dorico.files", "hbuc.dorico.dialog" }
  local saved = {}
  for _, name in ipairs(names) do saved[name] = package.loaded[name] end
  package.loaded["hbuc.dorico.files"] = {
    write = function(path, text) written[path] = text end,
    read = function(path) if path:match("response%.json$") then return answer end end,
  }
  package.loaded["hbuc.dorico.dialog"] = nil
  local execute, remove = os.execute, os.remove
  -- stand-ins for os.execute and os.remove, put back below
  os.execute = function(command) ran = command; return true, "exit", 0 end -- luacheck: ignore 122
  os.remove = function() end -- luacheck: ignore 122
  local ok, result = pcall(function()
    local log = { line = function(_, ...) if logged then logged[#logged + 1] = table.concat({ ... }, " ") end end }
    local ctx = { isWindows = isWindows, root = "r/", folders = { temp = "t/" }, log = log }
    return fn(require("hbuc.dorico.dialog"), ctx)
  end)
  os.execute, os.remove = execute, remove -- luacheck: ignore 122
  for _, name in ipairs(names) do package.loaded[name] = saved[name] end
  if not ok then error(result, 0) end
  return result, written, ran
end

local CHOICE = { title = "T", text = "Some text", buttons = { { id = "export", label = "Export MusicXML" },
  { id = "cancel", label = "Cancel" } }, cancel = "cancel" }

return {
  ask_file_and_command = function(t)
    local req = { version = "1", runId = "r" }
    local got, written, ran = exchange(true, function(d, ctx) return d.ask(ctx, req) end,
      '{"cancelled":true,"error":"no window"}')
    t:eq(got.error, "no window", "the settings dialog's answer comes back as it is, failure or not")
    t:eq(json.decode(written["t/request.json"]).runId, "r")
    t:ok(ran:find('-Request "t\\request.json" -Response "t\\response.json"', 1, true), ran)
    local _, _, mac = exchange(false, function(d, ctx) return d.ask(ctx, req) end, '{"cancelled":true}')
    t:ok(mac:find("'t/request.json' 't/response.json'", 1, true), mac)
  end,
  choice_file_and_command = function(t)
    local got, written, ran = exchange(true, function(d, ctx) return d.choose(ctx, CHOICE) end, '{"choice":"export"}')
    t:eq(got, "export")
    local sent = json.decode(written["t/choice.json"])
    t:eq(sent.buttons[1].label, "Export MusicXML")
    t:eq(sent.cancel, "cancel")
    t:ok(ran:find("-Choice", 1, true) and ran:find("-Response", 1, true), ran)
    local _, _, mac = exchange(false, function(d, ctx) return d.choose(ctx, CHOICE) end, '{"choice":"cancel"}')
    t:ok(mac:find("--choice", 1, true), mac)
  end,
  pick_returns_the_chosen_paths = function(t)
    local path = "C:/Users/\195\169/Bells & Chimes/a.musicxml"
    local got, written, ran = exchange(true, function(d, ctx)
      return d.pick(ctx, { title = "Pick", folder = "C:/x/", files = { "a.musicxml" },
        filter = { name = "MusicXML", extensions = { "musicxml", "xml" } } })
    end, json.encode({ files = { path } }))
    t:eq(#got, 1)
    t:eq(got[1], path, "passed through unchanged")
    t:eq(json.decode(written["t/pick.json"]).folder, "C:/x/")
    t:ok(ran:find("-Pick", 1, true), ran)
    local _, _, mac = exchange(false, function(d, ctx) return d.pick(ctx, { title = "Pick" }) end, '{"files":[]}')
    t:ok(mac:find("--pick", 1, true), mac)
  end,
  pick_paths_travel_as_bytes = function(t)
    -- Dorico's Lua opens files by their Windows code page name (spike/50_paths.py: lfs lists "Noël" as byte 235,
    -- and the UTF-8 name doesn't open), so on Windows paths go both ways as the bytes they are
    local got, written = exchange(true, function(d, ctx)
      return d.pick(ctx, { title = "Pick", folder = "C:/Flows from No\235l/", files = { "No\235l.musicxml" } })
    end, json.encode({ files = { "C:/Flows from No\195\171l/No\195\171l.musicxml" },
      filesBytes = { "433a2f466c6f77732066726f6d204e6feb6c2f4e6feb6c2e6d75736963786d6c" } }))
    local sent = json.decode(written["t/pick.json"])
    t:eq(sent.folderBytes, "433a2f466c6f77732066726f6d204e6feb6c2f")
    t:eq(sent.filesBytes[1], "4e6feb6c2e6d75736963786d6c")
    t:eq(got[1], "C:/Flows from No\235l/No\235l.musicxml", "the code page bytes, which io.open takes")
    local both = exchange(true, function(d, ctx) return { d.pick(ctx, { title = "Pick" }) } end,
      json.encode({ files = { "C:/No\195\171l.musicxml" }, filesBytes = { "433a2f4e6feb6c2e6d75736963786d6c" } }))
    t:eq(both[1][1], "C:/No\235l.musicxml")
    t:eq(both[2][1], "C:/No\195\171l.musicxml", "and each path in UTF-8, for messages")
  end,
  a_cancelled_pick_is_no_files = function(t)
    local got = exchange(true, function(d, ctx) return d.pick(ctx, { title = "Pick" }) end,
      '{"files":[],"filesBytes":[]}')
    t:eq(type(got), "table")
    t:eq(#got, 0)
  end,
  a_script_error_is_a_failure_and_logged = function(t)
    -- the scripts answer Cancel or no files when their window fails, with the error alongside
    local logged = {}
    t:eq(exchange(false, function(d, ctx) return d.choose(ctx, CHOICE) end, '{"choice":"cancel","error":"no AppKit"}',
      logged), nil)
    local found = false
    for _, line in ipairs(logged) do
      if line:find("no AppKit", 1, true) then found = true end
    end
    t:ok(found, "run.log has the script's error: " .. table.concat(logged, " | "))
    t:eq(exchange(true, function(d, ctx) return d.pick(ctx, { title = "Pick" }) end,
      '{"files":[],"filesBytes":[],"error":"boom"}'), nil)
  end,
  no_answer_is_a_failure = function(t)
    t:eq(exchange(true, function(d, ctx) return d.choose(ctx, CHOICE) end, nil), nil)
    t:eq(exchange(true, function(d, ctx) return d.pick(ctx, { title = "Pick" }) end, nil), nil)
    t:eq(exchange(true, function(d, ctx) return d.pick(ctx, { title = "Pick" }) end, "not json"), nil)
  end,
  message_carries_the_ok_label = function(t)
    local msg, ran = showWith(true)
    t:eq(msg.ok, "OK", "the button's label comes from constants.DIALOG")
    t:eq(msg.text, "Done")
    t:eq(msg.title, "Handbells Used Chart")
    t:ok(ran:find("-Message", 1, true), ran)
    t:ok(showWith(false).ok == "OK", "the Mac's too")
  end,
}
