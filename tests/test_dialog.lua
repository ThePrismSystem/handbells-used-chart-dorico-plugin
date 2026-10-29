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
local function exchange(isWindows, fn, answer)
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
    local ctx = { isWindows = isWindows, root = "r/", folders = { temp = "t/" }, log = { line = function() end } }
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
      return d.pick(ctx, { title = "Pick", folder = "C:/x/", file = "a.musicxml",
        filter = { name = "MusicXML", extensions = { "musicxml", "xml" } } })
    end, json.encode({ files = { path } }))
    t:eq(#got, 1)
    t:eq(got[1], path, "passed through unchanged")
    t:eq(json.decode(written["t/pick.json"]).folder, "C:/x/")
    t:ok(ran:find("-Pick", 1, true), ran)
    local _, _, mac = exchange(false, function(d, ctx) return d.pick(ctx, { title = "Pick" }) end, '{"files":[]}')
    t:ok(mac:find("--pick", 1, true), mac)
  end,
  no_answer_is_a_cancel = function(t)
    t:eq(exchange(true, function(d, ctx) return d.choose(ctx, CHOICE) end, nil), nil)
    t:eq(#exchange(true, function(d, ctx) return d.pick(ctx, { title = "Pick" }) end, nil), 0)
    t:eq(#exchange(true, function(d, ctx) return d.pick(ctx, { title = "Pick" }) end, "not json"), 0)
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
