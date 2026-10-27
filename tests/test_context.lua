-- A run that cannot even start says so. The dialog and the file helpers are stubbed, so nothing is shown or made.
local function failedWith(...)
  local shown
  local names = { "hbuc.dorico.dialog", "hbuc.dorico.files", "hbuc.dorico.context" }
  local saved = {}
  for _, name in ipairs(names) do saved[name] = package.loaded[name] end
  package.loaded["hbuc.dorico.dialog"] = {
    show = function(ctx, kind, text) shown = { ctx = ctx, kind = kind, text = text } end,
  }
  package.loaded["hbuc.dorico.files"] = { ensureDir = function() end }
  package.loaded["hbuc.dorico.context"] = nil
  local args = { n = select("#", ...), ... }
  local ok, err = pcall(function() require("hbuc.dorico.context").failed(unpack(args, 1, args.n)) end)
  for _, name in ipairs(names) do package.loaded[name] = saved[name] end
  if not ok then error(err, 0) end
  return shown
end

return {
  start_failure_is_shown = function(t)
    local shown = failedWith("root/", "guards.lua:17: APPDATA is not set", { TEMP = "Z:/no such folder" })
    t:eq(shown.kind, "error")
    t:eq(shown.text, "The plug-in could not start, so nothing was changed: APPDATA is not set")
    t:eq(shown.ctx.folders.temp, "Z:/no such folder/hbuc/", "the message goes through the temp folder")
    t:eq(shown.ctx.root, "root/")
  end,
  nowhere_to_write_shows_nothing = function(t)
    t:eq(failedWith("root/", "boom", {}, true), nil)
  end,
}
