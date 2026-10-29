-- Does File.Export?FilterID=MusicXMLExportFilter open Dorico's export dialog while a script runs, and does the
-- script get control back once the dialog closes? Records the wall clock before and after the command, and writes
-- <run>/46-started.txt first so the driver (spike/46_export_dialog.py) can tell the dialog apart from the run's end.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "lib/?.lua"
for name in pairs(package.loaded) do
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("46_export_dialog", function(p)
  local app = DoApp.DoApp()
  p:fact("flowCount", #app.currentScore.flows)
  local started = os.time()
  local f = assert(io.open(probe.runDir .. "46-started.txt", "wb"))
  f:write(tostring(started))
  f:close()
  local ok, result = pcall(function() return app:doCommand("File.Export?FilterID=MusicXMLExportFilter") end)
  local returned = os.time()
  p:fact("commandOk", ok)
  p:fact("commandResult", tostring(result))
  p:fact("started", started)
  p:fact("returned", returned)
  p:fact("secondsInCommand", returned - started)
end)
