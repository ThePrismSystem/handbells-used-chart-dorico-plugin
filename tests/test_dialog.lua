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

local CHOICE = { title = "T", text = "Some text", buttons = { { id = "combine", label = "Combine" },
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
    local got, written, ran = exchange(true, function(d, ctx) return d.choose(ctx, CHOICE) end, '{"choice":"combine"}')
    t:eq(got, "combine")
    local sent = json.decode(written["t/choice.json"])
    t:eq(sent.buttons[1].label, "Combine")
    t:eq(sent.cancel, "cancel")
    t:ok(ran:find("-Choice", 1, true) and ran:find("-Response", 1, true), ran)
    local _, _, mac = exchange(false, function(d, ctx) return d.choose(ctx, CHOICE) end, '{"choice":"cancel"}')
    t:ok(mac:find("--choice", 1, true), mac)
  end,
  a_script_error_is_a_failure_and_logged = function(t)
    -- the scripts answer Cancel when their window fails, with the error alongside
    local logged = {}
    t:eq(exchange(false, function(d, ctx) return d.choose(ctx, CHOICE) end, '{"choice":"cancel","error":"no AppKit"}',
      logged), nil)
    local found = false
    for _, line in ipairs(logged) do
      if line:find("no AppKit", 1, true) then found = true end
    end
    t:ok(found, "run.log has the script's error: " .. table.concat(logged, " | "))
  end,
  no_answer_is_a_failure = function(t)
    t:eq(exchange(true, function(d, ctx) return d.choose(ctx, CHOICE) end, nil), nil)
    t:eq(exchange(true, function(d, ctx) return d.choose(ctx, CHOICE) end, "not json"), nil)
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
