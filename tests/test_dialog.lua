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
  os.execute = function(command) ran = command; return true, "exit", 0 end
  local ok, err = pcall(function()
    local ctx = { isWindows = isWindows, root = "r/", folders = { temp = "t/" }, log = { line = function() end } }
    require("hbuc.dorico.dialog").show(ctx, "info", "Done")
  end)
  os.execute = execute
  for _, name in ipairs(names) do package.loaded[name] = saved[name] end
  if not ok then error(err, 0) end
  return json.decode(written), ran
end

return {
  message_carries_the_ok_label = function(t)
    local msg, ran = showWith(true)
    t:eq(msg.ok, "OK", "the button's label comes from constants.DIALOG")
    t:eq(msg.text, "Done")
    t:eq(msg.title, "Handbells Used Chart")
    t:ok(ran:find("-Message", 1, true), ran)
    t:ok(showWith(false).ok == "OK", "the Mac's too")
  end,
}
